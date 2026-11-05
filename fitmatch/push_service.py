import os
import time
import logging
from typing import Optional, Dict, Any, List
import httpx
try:
    import jwt
except ImportError:
    jwt = None

logger = logging.getLogger("fitmatch.push_service")


class APNsPushService:
    """Production Apple Push Notification service (APNs) client.
    
    Implements Apple APNs HTTP/2 protocol with token-based authentication (JWT / ES256).
    Handles development sandbox and production gateways, automatic JWT caching,
    and fallback diagnostic mode when credentials are being set up.
    """

    SANDBOX_URL = "https://api.sandbox.push.apple.com"
    PRODUCTION_URL = "https://api.push.apple.com"

    def __init__(
        self,
        team_id: Optional[str] = None,
        bundle_id: Optional[str] = None,
        key_id: Optional[str] = None,
        key_path: Optional[str] = None,
        key_content: Optional[str] = None,
        use_sandbox: bool = True
    ):
        self.team_id = team_id or os.getenv("APNS_TEAM_ID", "6F8J3B65D7")
        self.bundle_id = bundle_id or os.getenv("APNS_BUNDLE_ID", "com.lucaberardi06.frontend")
        self.key_id = key_id or os.getenv("APNS_KEY_ID")
        self.key_path = key_path or os.getenv("APNS_KEY_PATH")
        self.key_content = key_content or os.getenv("APNS_KEY_P8")
        
        # In development/TestFlight, sandbox is standard; production for App Store
        env_sandbox = os.getenv("APNS_USE_SANDBOX")
        if env_sandbox is not None:
            self.use_sandbox = env_sandbox.lower() in ("true", "1", "yes")
        else:
            self.use_sandbox = use_sandbox

        self._private_key: Optional[str] = None
        self._cached_jwt: Optional[str] = None
        self._jwt_created_at: float = 0.0

        self._load_private_key()

    def _load_private_key(self):
        """Loads the ES256 .p8 private key if provided via file or string."""
        if self.key_content and "PRIVATE KEY" in self.key_content:
            self._private_key = self.key_content.strip()
            return

        if self.key_path and os.path.exists(self.key_path):
            try:
                with open(self.key_path, "r", encoding="utf-8") as f:
                    self._private_key = f.read().strip()
            except Exception as e:
                logger.error(f"[APNs] Failed to read private key from {self.key_path}: {e}")

    @property
    def is_configured(self) -> bool:
        """Returns True if APNs authentication credentials (.p8 key and key_id) are present."""
        return bool(self._private_key and self.key_id and self.team_id and self.bundle_id)

    def get_status(self) -> Dict[str, Any]:
        """Returns the current APNs service diagnostic and configuration state."""
        return {
            "is_configured": self.is_configured,
            "team_id": self.team_id,
            "bundle_id": self.bundle_id,
            "key_id": self.key_id if self.key_id else "NON_CONFIGURATO",
            "has_private_key": bool(self._private_key),
            "environment": "sandbox" if self.use_sandbox else "production",
            "protocol": "Apple HTTP/2 (RFC 7540)"
        }

    def _get_auth_token(self) -> Optional[str]:
        """Generates or reuses cached APNs provider bearer JWT (valid for 50 minutes)."""
        if jwt is None or not self._private_key or not self.key_id or not self.team_id:
            return None

        now = time.time()
        if self._cached_jwt and (now - self._jwt_created_at) < 3000:
            return self._cached_jwt

        try:
            headers = {
                "alg": "ES256",
                "kid": self.key_id
            }
            payload = {
                "iss": self.team_id,
                "iat": int(now)
            }
            token = jwt.encode(payload, self._private_key, algorithm="ES256", headers=headers)
            self._cached_jwt = token
            self._jwt_created_at = now
            return token
        except Exception as e:
            logger.error(f"[APNs] Error generating ES256 JWT for APNs: {e}")
            return None

    async def send_push(
        self,
        device_token: str,
        title: str,
        body: str,
        subtitle: Optional[str] = None,
        badge: int = 1,
        sound: str = "default",
        custom_data: Optional[Dict[str, Any]] = None,
        environment: Optional[str] = None
    ) -> Dict[str, Any]:
        """Sends a high-priority push notification to an iOS device token."""
        clean_token = device_token.strip().replace(" ", "").replace("<", "").replace(">", "")
        if not clean_token:
            return {"status": "error", "reason": "empty_device_token"}

        # If APNs .p8 key is not yet configured, provide simulation fallback
        if not self.is_configured:
            logger.info(
                f"[APNs Simulation] Credentials pending. Simulating push to device {clean_token[:10]}... | "
                f"Title: '{title}' | Body: '{body}'"
            )
            return {
                "status": "simulated",
                "reason": "credentials_pending",
                "message": "APNs credentials pending (.p8 key). Push logged and in-app feed updated.",
                "device_token": clean_token,
                "title": title
            }

        jwt_token = self._get_auth_token()
        if not jwt_token:
            return {"status": "error", "reason": "jwt_generation_failed"}

        # Select gateway base URL based on device environment or default
        use_sandbox = self.use_sandbox
        if environment:
            use_sandbox = (environment.lower() == "sandbox")
        base_url = self.SANDBOX_URL if use_sandbox else self.PRODUCTION_URL
        url = f"{base_url}/3/device/{clean_token}"

        alert_dict: Dict[str, Any] = {
            "title": title,
            "body": body
        }
        if subtitle:
            alert_dict["subtitle"] = subtitle

        payload: Dict[str, Any] = {
            "aps": {
                "alert": alert_dict,
                "sound": sound,
                "badge": badge
            }
        }
        if custom_data:
            for k, v in custom_data.items():
                if k != "aps":
                    payload[k] = v

        headers = {
            "authorization": f"bearer {jwt_token}",
            "apns-topic": self.bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",  # Immediate delivery
            "apns-expiration": "0"
        }

        try:
            async with httpx.AsyncClient(http2=True, timeout=10.0) as client:
                response = await client.post(url, json=payload, headers=headers)
                if response.status_code == 200:
                    apns_id = response.headers.get("apns-id")
                    logger.info(f"[APNs] Push delivered successfully to {clean_token[:10]}... (apns-id: {apns_id})")
                    return {
                        "status": "sent",
                        "status_code": 200,
                        "apns_id": apns_id,
                        "device_token": clean_token
                    }
                else:
                    err_body = response.text
                    logger.warning(f"[APNs] Delivery failed ({response.status_code}): {err_body}")
                    return {
                        "status": "failed",
                        "status_code": response.status_code,
                        "reason": err_body,
                        "device_token": clean_token
                    }
        except Exception as e:
            logger.error(f"[APNs] Network error during push delivery: {e}")
            return {
                "status": "error",
                "reason": str(e),
                "device_token": clean_token
            }
