"""Read-only Stripe account check for the running podcast container.

Run with ``python -m podcast_service.stripe_diagnostic``. Never prints keys.
"""

import os
import re
import sys

import httpx


def main() -> int:
    secret = os.environ.get("STRIPE_SECRET_KEY", "")
    mode = "live" if secret.startswith("sk_live_") else (
        "test" if secret.startswith("sk_test_") else "missing_or_invalid")
    print(f"stripe_key_mode={mode}")
    print(f"stripe_key_has_whitespace={any(c.isspace() for c in secret)}")
    print(f"stripe_key_has_quotes={chr(34) in secret or chr(39) in secret}")
    print(f"webhook_secret_configured={os.environ.get('STRIPE_WEBHOOK_SECRET', '').startswith('whsec_')}")
    if mode == "missing_or_invalid":
        return 1
    try:
        response = httpx.get(
            "https://api.stripe.com/v1/account",
            headers={"Authorization": f"Bearer {secret}"}, timeout=15,
            follow_redirects=False,
        )
    except httpx.HTTPError as error:
        print(f"stripe_connection_error={type(error).__name__}")
        return 1
    print(f"stripe_account_http={response.status_code}")
    request_id = response.headers.get("Request-Id", "")
    if re.fullmatch(r"req_[A-Za-z0-9]{1,100}", request_id):
        print(f"stripe_request_id={request_id}")
    try:
        data = response.json()
    except ValueError:
        print("stripe_response=invalid_json")
        return 1
    if response.status_code != 200:
        error = data.get("error", {}) if isinstance(data, dict) else {}
        code = error.get("code", "unknown") if isinstance(error, dict) else "unknown"
        if not isinstance(code, str) or not re.fullmatch(r"[a-z0-9_]{1,80}", code):
            code = "unknown"
        print(f"stripe_error_code={code}")
        error_type = error.get("type", "unknown") if isinstance(error, dict) else "unknown"
        if not isinstance(error_type, str) or not re.fullmatch(r"[a-z0-9_]{1,80}", error_type):
            error_type = "unknown"
        print(f"stripe_error_type={error_type}")
        # Classify only: raw messages can contain API keys.
        message = str(error.get("message", "")).lower() if isinstance(error, dict) else ""
        reason = "unclassified"
        for fragment, category in (("expired", "expired_key"), ("invalid api key", "invalid_key"),
                                   ("no api key", "missing_key"), ("permission", "permission_denied"),
                                   ("ip address", "ip_restriction"), ("revoked", "revoked_key")):
            if fragment in message:
                reason = category
                break
        print(f"stripe_error_reason={reason}")
        print(f"stripe_error_object_present={bool(error)}")
        return 1
    if not isinstance(data, dict):
        print("stripe_response=unexpected_shape")
        return 1
    print(f"stripe_account_id={data.get('id', 'unknown')}")
    print(f"charges_enabled={data.get('charges_enabled')}")
    capabilities = data.get("capabilities") or {}
    print(f"card_payments={capabilities.get('card_payments', 'unknown')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
