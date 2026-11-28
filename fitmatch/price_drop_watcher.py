import logging
import os
import urllib.parse
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
from fitmatch.supabase_client import SupabaseClient
from fitmatch.push_service import APNsPushService

logger = logging.getLogger("fitmatch.price_watcher")


def _normalize_size_token(raw: str) -> str:
    clean = (raw or "").strip().lower().replace(",", ".")
    for prefix in ("eu ", "eur ", "it "):
        if clean.startswith(prefix):
            clean = clean[len(prefix):].strip()
    if clean.endswith(" eu"):
        clean = clean[:-3].strip()
    clean = clean.replace(" 1/2", ".5").replace(" 2/3", ".5").replace(" 1/3", ".5")
    return clean


def _offer_matches_size(available_sizes: Optional[List[Any]], required_size: str) -> bool:
    if not available_sizes:
        return False
    target = _normalize_size_token(required_size)
    if not target:
        return True
    try:
        target_num = float(target)
    except ValueError:
        target_num = None

    for raw_sz in available_sizes:
        sz = _normalize_size_token(str(raw_sz))
        if not sz:
            continue
        if sz == target:
            return True
        if target_num is not None:
            try:
                if abs(float(sz) - target_num) < 0.35:
                    return True
            except ValueError:
                pass
    return False


class PriceDropWatcher:
    """Automated server-side monitor for price drops on user saved items (Wishlist).

    Resolves live offers directly via `store_offers.product_id` (preventing fuzzy
    cross-product mismatches), validates size availability and user target thresholds,
    inserts in-app notifications, dispatches APNs pushes, and keeps wishlist snapshot
    fields (`current_price`, `store_id`, `store_name`, `product_url`, `discount_pct`)
    in sync.
    """

    def __init__(self, supabase: Optional[SupabaseClient] = None, push_service: Optional[APNsPushService] = None):
        if supabase is not None:
            self.supabase = supabase
        else:
            service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
            self.supabase = SupabaseClient(api_key=service_key) if service_key else SupabaseClient()
        self.push_service = push_service or APNsPushService()

    def _fetch_live_offers_for_group(
        self,
        product_id: Optional[str],
        canonical_name: str,
    ) -> List[Dict[str, Any]]:
        """Fetch live in-stock offers anchored by product_id when available."""
        if product_id:
            q_pid = urllib.parse.quote(product_id, safe="")
            resp = self.supabase._request(
                f"store_offers?product_id=eq.{q_pid}"
                f"&in_stock=neq.false&current_price=gt.0"
                f"&order=current_price.asc&limit=60"
                f"&select=id,product_id,store_id,store_name,current_price,original_price,discount_pct,product_url,image_url,available_sizes"
            )
            rows = resp.get("data") or []
            if rows:
                return [
                    {
                        "id": r.get("id"),
                        "product_id": r.get("product_id"),
                        "store_id": r.get("store_id"),
                        "store_name": r.get("store_name"),
                        "price": float(r.get("current_price") or 0.0),
                        "original_price": r.get("original_price"),
                        "discount_pct": r.get("discount_pct"),
                        "url": r.get("product_url"),
                        "image_url": r.get("image_url"),
                        "available_sizes": r.get("available_sizes") or [],
                    }
                    for r in rows
                    if float(r.get("current_price") or 0.0) > 0
                ]

        # Fallback to indexed search ONLY if product_id is unavailable
        live_matches = self.supabase.search_indexed(canonical_name)
        if not live_matches:
            return []
        top_product = live_matches[0]
        return top_product.get("offers") or []

    async def run_check(self, min_drop_amount: float = 1.0) -> Dict[str, Any]:
        """Runs a complete price drop scan across all user wishlists and alerts."""
        logger.info("[Watcher] Starting server-side price drop check...")
        stats = {
            "wishlist_items_scanned": 0,
            "drops_detected": 0,
            "notifications_dispatched": 0,
            "devices_notified": 0,
            "items_updated": []
        }

        # 1. Fetch active wishlist items from Supabase
        try:
            resp = self.supabase._request("wishlists?select=*&limit=1000")
            wishlist_rows = resp.get("data") or []
        except Exception as e:
            logger.error(f"[Watcher] Failed to fetch wishlists from Supabase: {e}")
            return stats

        stats["wishlist_items_scanned"] = len(wishlist_rows)
        if not wishlist_rows:
            logger.info("[Watcher] No wishlist items currently registered.")
            return stats

        # Group by (product_id or lower(canonical_name)) to minimize DB queries
        grouped: Dict[str, Dict[str, Any]] = {}
        for row in wishlist_rows:
            c_name = (row.get("canonical_name") or "").strip()
            pid = (row.get("product_id") or "").strip() or None
            if not c_name and not pid:
                continue
            key = f"pid:{pid}" if pid else f"name:{c_name.lower()}"
            bucket = grouped.setdefault(key, {"product_id": pid, "canonical_name": c_name, "items": []})
            bucket["items"].append(row)

        for _, group in grouped.items():
            pid = group["product_id"]
            c_name = group["canonical_name"]
            user_items = group["items"]

            try:
                offers = self._fetch_live_offers_for_group(pid, c_name)
            except Exception as e:
                logger.warning(f"[Watcher] Live offer lookup failed for '{c_name}' (pid={pid}): {e}")
                continue

            if not offers:
                continue

            for item in user_items:
                device_id = item.get("device_id")
                user_id = item.get("user_id")
                if not device_id and not user_id:
                    continue

                if item.get("is_alert_enabled") is False:
                    continue

                old_price = float(item.get("current_price") or 0.0)
                if old_price <= 0:
                    continue

                req_size = (item.get("selected_size") or "").strip()
                is_specific_size = bool(
                    req_size and req_size.lower() not in (
                        "standard", "tutte", "tutte le taglie", "all", "none", "", "default"
                    )
                )
                target_price = float(item["target_alert_price"]) if item.get("target_alert_price") is not None else None

                valid_offers = []
                for o in offers:
                    o_price = float(o.get("price") or o.get("current_price") or 0.0)
                    if o_price <= 0:
                        continue
                    # Sanity guard when product_id was not anchored: avoid cross-category mismatches
                    if not pid and old_price >= 60.0 and o_price < (old_price * 0.35):
                        continue
                    if is_specific_size and not _offer_matches_size(o.get("available_sizes"), req_size):
                        continue
                    valid_offers.append(o)

                if not valid_offers:
                    continue

                best_offer = min(valid_offers, key=lambda x: float(x.get("price") or x.get("current_price") or 0.0))
                best_price = float(best_offer.get("price") or best_offer.get("current_price") or 0.0)

                is_target_reached = bool(target_price is not None and best_price <= target_price + 0.01)
                if target_price is not None and not is_target_reached:
                    continue

                if best_price >= (old_price - min_drop_amount):
                    continue

                savings = old_price - best_price
                disc_pct = round((savings / old_price) * 100.0, 1) if old_price > 0 else 0.0
                store_id = best_offer.get("store_id") or item.get("store_id")
                store_name = best_offer.get("store_name") or item.get("store_name") or "Negozio Partner"
                offer_url = best_offer.get("url") or best_offer.get("product_url") or item.get("product_url")
                img_url = best_offer.get("image_url") or item.get("image_url")

                notif_type = "target_reached" if is_target_reached else "price_drop"

                if is_target_reached:
                    title = "🎯 Soglia Raggiunta FitMatch!"
                    subtitle = f"{c_name} è sceso sotto €{target_price:.2f}!"
                    body = f"Nuovo prezzo: €{best_price:.2f} su {store_name} (era €{old_price:.2f}). Approfittane subito!"
                else:
                    title = "🔥 Calo Prezzo FitMatch!"
                    subtitle = f"{c_name} è calato di €{savings:.2f} (-{disc_pct:.0f}%)"
                    body = f"Nuovo miglior prezzo: €{best_price:.2f} su {store_name} (era €{old_price:.2f})."

                stats["drops_detected"] += 1
                logger.info(f"[Watcher] Price drop detected for '{c_name}': €{old_price:.2f} -> €{best_price:.2f} on {store_name}")

                # 1. Insert in-app notification in Supabase
                notif_id = str(uuid.uuid4())
                notif_payload = {
                    "id": notif_id,
                    "device_id": device_id,
                    "user_id": user_id,
                    "type": notif_type,
                    "title": title,
                    "subtitle": subtitle,
                    "body": body,
                    "product_canonical_name": c_name,
                    "store_id": store_id,
                    "store_name": store_name,
                    "old_price": old_price,
                    "new_price": best_price,
                    "discount_pct": disc_pct,
                    "action_url": offer_url,
                    "image_url": img_url,
                    "is_read": False
                }
                try:
                    self.supabase._request("notifications", method="POST", data=notif_payload)
                    stats["notifications_dispatched"] += 1
                except Exception as e:
                    logger.error(f"[Watcher] Error recording notification in Supabase: {e}")

                # 2. Find device tokens and dispatch APNs push
                if device_id:
                    try:
                        q_dev = urllib.parse.quote(str(device_id), safe="")
                        tokens_resp = self.supabase._request(f"device_tokens?device_id=eq.{q_dev}&is_active=eq.true&select=*")
                        tokens = tokens_resp.get("data") or []
                        for t_rec in tokens:
                            token = t_rec.get("device_token")
                            env = t_rec.get("environment", "production")
                            min_pct = float(t_rec.get("min_discount_pct") or 0.0)

                            if not is_target_reached and disc_pct < min_pct:
                                continue

                            custom_data = {
                                "notification_id": notif_id,
                                "product": c_name,
                                "type": notif_type,
                                "url": offer_url,
                                "price": best_price,
                                "old_price": old_price,
                                "store_name": store_name,
                                "store_id": store_id,
                                "image_url": img_url
                            }
                            await self.push_service.send_push(
                                device_token=token,
                                title=title,
                                subtitle=subtitle,
                                body=body,
                                sound="default",
                                custom_data=custom_data,
                                environment=env
                            )
                            stats["devices_notified"] += 1
                    except Exception as e:
                        logger.error(f"[Watcher] Error dispatching push to device {device_id}: {e}")

                # 3. Sync full best-offer snapshot on wishlist row (keeping saved_price untouched!)
                try:
                    w_id = item.get("id")
                    if w_id:
                        orig_price = float(item.get("original_price") or best_offer.get("original_price") or 0.0)
                        updated_disc = (
                            round(((orig_price - best_price) / orig_price) * 100.0, 1)
                            if orig_price > best_price
                            else float(best_offer.get("discount_pct") or 0.0)
                        )
                        patch_payload: Dict[str, Any] = {
                            "current_price": best_price,
                            "store_name": store_name,
                            "discount_pct": updated_disc,
                            "updated_at": datetime.now(timezone.utc).isoformat(),
                        }
                        if store_id:
                            patch_payload["store_id"] = store_id
                        if offer_url:
                            patch_payload["product_url"] = offer_url
                        if img_url:
                            patch_payload["image_url"] = img_url
                        resolved_pid = best_offer.get("product_id") or pid
                        if resolved_pid and not item.get("product_id"):
                            patch_payload["product_id"] = resolved_pid

                        self.supabase._request(
                            f"wishlists?id=eq.{w_id}",
                            method="PATCH",
                            data=patch_payload
                        )
                        stats["items_updated"].append({"id": w_id, "name": c_name, "new_price": best_price})
                except Exception as e:
                    logger.error(f"[Watcher] Error updating wishlist item price: {e}")

        logger.info(f"[Watcher] Price drop check complete: {stats}")
        return stats
