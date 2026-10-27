"""JWT validation-notebook inputs and token acquisition; token bytes stay in memory."""

import base64
import binascii
import json
import math
import time
from collections.abc import Mapping
from typing import Any

import requests

from validationtools import ValidationError, _run_json


def jwt_configuration(
    config: Mapping[str, Any], account: Mapping[str, Any], *,
    client_secret: str = "", no_role_token: str = "", user_token: str = "",
) -> dict[str, str]:
    from utils import require_inputs

    tenant = config.get("entra_tenant_id") or account.get("tenantId", "")
    client = config.get("entra_client_id", "")
    audience = config.get("entra_audience") or (f"api://{client}" if client else "")
    values = {
        "tenant_id": tenant,
        "client_id": client,
        "audience": audience,
        "resource_id": config.get("entra_resource_id") or audience.removeprefix("api://"),
        "client_secret": client_secret or config.get("VALIDATION_ENTRA_CLIENT_SECRET")
        or config.get("ENTRA_CLIENT_SECRET", ""),
        "negative_client_id": config.get("ENTRA_VALIDATION_NEGATIVE_CLIENT_ID", ""),
        "negative_client_secret": config.get("ENTRA_VALIDATION_NEGATIVE_CLIENT_SECRET", ""),
        "no_role_token": no_role_token or config.get("VALIDATION_JWT_NO_ROLE_TOKEN", ""),
        "user_token": user_token or config.get("VALIDATION_JWT_DEVICE_TOKEN", ""),
    }
    required = {f"entra.{key}": values[key] for key in (
        "tenant_id", "client_id", "audience", "resource_id", "client_secret",
    )}
    if not values["no_role_token"]:
        required.update({f"entra.{key}": values[key] for key in (
            "negative_client_id", "negative_client_secret",
        )})
    require_inputs(required)
    if not all(isinstance(value, str) for value in values.values()):
        raise ValidationError("JWT configuration values must be strings.")
    return values


def decode_jwt(token: str) -> tuple[dict[str, Any], dict[str, Any]]:
    """Decode locally without claiming to verify the JWT signature."""
    if not isinstance(token, str) or len(token.split(".")) != 3 or not all(token.split(".")):
        raise ValidationError("JWT must have three nonempty segments.")
    decoded = []
    try:
        for part in token.split(".")[:2]:
            data = base64.b64decode(part + "=" * (-len(part) % 4), altchars=b"-_", validate=True)
            value = json.loads(data)
            if not isinstance(value, dict):
                raise ValueError
            decoded.append(value)
    except (ValueError, UnicodeError, binascii.Error):
        raise ValidationError("JWT header and payload must be base64url JSON objects.") from None
    return decoded[0], decoded[1]


def validate_jwt(
    token: str, *, tenant_id: str, resource_id: str, client_id: str = "",
    user_id: str = "", required_role: str = "", forbidden_role: str = "",
    delegated: bool = False,
) -> dict[str, Any]:
    """Check scenario claims; APIM is responsible for cryptographic validation."""
    header, claims = decode_jwt(token)
    errors = []
    if header.get("alg") != "RS256" or not header.get("kid"):
        errors.append("expected an Entra RS256 signing key")
    if claims.get("ver") != "2.0":
        errors.append("expected a v2 access token")
    if claims.get("aud") != resource_id:
        errors.append("audience does not match the gateway resource client ID")
    if claims.get("tid") != tenant_id or claims.get("iss") != f"https://login.microsoftonline.com/{tenant_id}/v2.0":
        errors.append("tenant or issuer does not match setup")
    now = time.time()
    for key in ("iat", "nbf", "exp"):
        value = claims.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            errors.append(f"{key} must be a numeric timestamp")
        elif key == "exp" and value <= now + 30:
            errors.append("token is expired or expires within 30 seconds")
        elif key in ("iat", "nbf") and value > now + 60:
            errors.append(f"{key} is in the future")
    roles = claims.get("roles", [])
    if not isinstance(roles, list) or not all(isinstance(role, str) for role in roles):
        errors.append("roles must be a string array")
        roles = []
    if required_role and required_role.casefold() not in [role.casefold() for role in roles]:
        errors.append(f"required role {required_role} is missing; rerun setup and acquire a fresh token")
    if forbidden_role and forbidden_role.casefold() in [role.casefold() for role in roles]:
        errors.append(f"negative token unexpectedly has {forbidden_role}")
    scope = claims.get("scp", "")
    if delegated:
        if not isinstance(scope, str) or "access_as_user" not in scope.split():
            errors.append("delegated token is missing access_as_user")
        if not user_id or claims.get("oid") != user_id:
            errors.append("delegated token is not for the current signed-in user")
    elif scope or not client_id or claims.get("azp") != client_id:
        errors.append("application token does not match the expected client-credentials identity")
    if errors:
        raise ValidationError("JWT scenario claims failed: " + "; ".join(errors))
    return {
        "header": {key: header.get(key) for key in ("alg", "kid", "typ")},
        "claims": {key: claims.get(key) for key in (
            "ver", "aud", "iss", "tid", "azp", "oid", "scp", "roles", "iat", "nbf", "exp",
        )},
        "required_role": required_role or None,
        "forbidden_role": forbidden_role or None,
        "claim_checks": "PASS",
        "signature_validation": "Not performed by decoding; proven by the APIM request tests.",
    }


def acquire_application_token(tenant_id: str, audience: str, client_id: str, client_secret: str) -> str:
    try:
        response = requests.post(
            f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token",
            data={"grant_type": "client_credentials", "client_id": client_id,
                  "client_secret": client_secret, "scope": f"{audience}/.default"},
            timeout=30,
        )
    except requests.RequestException:
        raise ValidationError("Entra token request could not complete; check network access.") from None
    if response.status_code != 200:
        raise ValidationError(
            f"Entra client-credentials request failed (HTTP {response.status_code}). "
            "Check setup credentials, direct assignments and tenant policy; token responses are not printed."
        )
    try:
        data = response.json()
    except ValueError:
        raise ValidationError("Entra token response is not JSON.") from None
    if not isinstance(data, dict) or not isinstance(data.get("access_token"), str) or not data["access_token"]:
        raise ValidationError("Entra response did not contain an access token.")
    return data["access_token"]


def signed_in_user(account: Mapping[str, Any]) -> str:
    if account.get("user", {}).get("type", "").lower() != "user":
        raise ValidationError("User-token validation requires Azure CLI signed in as a user (az login), not an SP.")
    profile = _run_json(["az", "ad", "signed-in-user", "show", "--output", "json"])
    if not isinstance(profile, dict) or not isinstance(profile.get("id"), str) or not profile["id"]:
        raise ValidationError("Azure CLI did not return the signed-in user's object ID.")
    return profile["id"]


def acquire_user_token(tenant_id: str, audience: str) -> str:
    try:
        result = _run_json([
            "az", "account", "get-access-token", "--tenant", tenant_id,
            "--scope", f"{audience}/access_as_user", "--output", "json",
        ])
    except ValidationError as error:
        raise ValidationError(
            "Cannot acquire the current Azure CLI user's gateway token. "
            "Run setup as that user; if Entra requires renewed sign-in/MFA, run "
            f"'az login --tenant {tenant_id} --scope {audience}/access_as_user', then rerun this cell. "
            "No device-flow or different-identity fallback was used."
        ) from error
    if not isinstance(result, dict) or not isinstance(result.get("accessToken"), str) or not result["accessToken"]:
        raise ValidationError("Azure CLI did not return a user access token.")
    return result["accessToken"]
