import logging
import uuid
from typing import Dict, Any, List, Optional
from fitmatch.supabase_client import SupabaseClient
from fitmatch.push_service import APNsPushService

logger = logging.getLogger("fitmatch.price_watcher")


class PriceDropWatcher:
    """Automated server-side monitor for price drops on user saved items (Wishlist).
    
    Inspects live store offers against monitored items in Supabase, validates
    size availability and minimum discount thresholds, inserts in-app notification
    records, and dispatches real-time APNs push notifications to users' devices.
    """

    def __init__(self, supabase: Optional[SupabaseClient] = None, push_service: Optional[APNsPushService] = None):
        self.supabase = supabase or SupabaseClient()
        self.push_service = push_service or APNsPushService()

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

        # Group by canonical_name to minimize search queries
        grouped: Dict[str, List[Dict[str, Any]]] = {}
        for row in wishlist_rows:
            c_name = row.get("canonical_name")
            if c_name:
                grouped.setdefault(c_name, []).append(row)

        for c_name, user_items in grouped.items():
            # Find best live offer across partner stores
            try:
                live_matches = self.supabase.search_indexed(c_name)
            except Exception as e:
                logger.warning(f"[Watcher] Search failed for '{c_name}': {e}")
                continue

            if not live_matches:
                continue

            top_product = live_matches[0]
            offers = top_product.get("offers") or []
            if not offers:
                continue

            for item in user_items:
                device_id = item.get("device_id")
                if not device_id:
                    continue

                # Respect user alert toggle
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
                target_price = float(item["target_alert_price"]) if item.get("target_alert_price") else None

                # Find best offer that has user size if requested
                valid_offers = []
                for o in offers:
                    o_price = float(o.get("price") or 0.0)
                    if o_price <= 0:
                        continue
                    if is_specific_size:
                        sizes = o.get("available_sizes") or []
                        if not any(s.strip().lower() == req_size.lower() for s in sizes):
                            continue
                    valid_offers.append(o)

                if not valid_offers:
                    continue

                best_offer = min(valid_offers, key=lambda x: float(x.get("price") or 0.0))
                best_price = float(best_offer.get("price") or 0.0)

                # Check if target price constraint applies
                is_target_reached = bool(target_price and best_price <= target_price)
                if target_price and not is_target_reached:
                    continue

                # Check if price actually dropped by at least min_drop_amount
                if best_price >= (old_price - min_drop_amount):
                    continue

                savings = old_price - best_price
                disc_pct = round((savings / old_price) * 100.0, 1) if old_price > 0 else 0.0
                store_name = best_offer.get("store_name") or "Negozio Partner"
                offer_url = best_offer.get("url") or item.get("product_url")
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
                    "user_id": item.get("user_id"),
                    "type": notif_type,
                    "title": title,
                    "subtitle": subtitle,
                    "body": body,
                    "product_canonical_name": c_name,
                    "store_id": best_offer.get("store_id"),
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
                try:
                    tokens_resp = self.supabase._request(f"device_tokens?device_id=eq.{device_id}&is_active=eq.true&select=*")
                    tokens = tokens_resp.get("data") or []
                    for t_rec in tokens:
                        token = t_rec.get("device_token")
                        env = t_rec.get("environment", "production")
                        min_pct = float(t_rec.get("min_discount_pct") or 0.0)

                        if disc_pct < min_pct:
                            continue

                        custom_data = {
                            "notification_id": notif_id,
                            "product": c_name,
                            "type": notif_type,
                            "url": offer_url,
                            "price": best_price,
                            "old_price": old_price,
                            "store_name": store_name,
                            "store_id": best_offer.get("store_id"),
                            "image_url": img_url
                        }
                        push_res = await self.push_service.send_push(
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

                # 3. Update current_price on wishlist row to prevent duplicate alerts
                try:
                    w_id = item.get("id")
                    if w_id:
                        self.supabase._request(
                            f"wishlists?id=eq.{w_id}",
                            method="PATCH",
                            data={"current_price": best_price}
                        )
                        stats["items_updated"].append({"id": w_id, "name": c_name, "new_price": best_price})
                except Exception as e:
                    logger.error(f"[Watcher] Error updating wishlist item price: {e}")

        logger.info(f"[Watcher] Price drop check complete: {stats}")
        return stats
