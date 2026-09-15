"""Test-only RSA key pairs and a fake JWKS/token factory (never used outside tests)."""

import base64
import hashlib
import hmac
import json
import time
from typing import Any

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPrivateKey
from jwt.algorithms import RSAAlgorithm

ISSUER = "https://test-vinayak.duckdns.org/auth/realms/app"
JWKS_URL = "http://keycloak:8080/auth/realms/app/protocol/openid-connect/certs"
AUDIENCE = "api"
AZP = "web-bff"


def generate_key(kid: str) -> tuple[str, RSAPrivateKey, dict[str, Any]]:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk: dict[str, Any] = dict(RSAAlgorithm.to_jwk(private_key.public_key(), as_dict=True))
    jwk.update({"kid": kid, "alg": "RS256", "use": "sig"})
    return kid, private_key, jwk


KID_A, PRIVATE_A, JWK_A = generate_key("kid-a")
KID_B, PRIVATE_B, JWK_B = generate_key("kid-b")


def jwks(*jwks_entries: dict[str, Any]) -> dict[str, Any]:
    return {"keys": list(jwks_entries)}


def public_pem(private_key: RSAPrivateKey) -> bytes:
    return private_key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )


def make_claims(**overrides: Any) -> dict[str, Any]:
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": ISSUER,
        "aud": AUDIENCE,
        "azp": AZP,
        "sub": "user-a",
        "typ": "Bearer",
        "iat": now,
        "nbf": now,
        "exp": now + 300,
        "preferred_username": "alice",
        "name": "Alice Example",
        "email": "alice@example.com",
        "realm_access": {"roles": ["user"]},
    }
    for key, value in overrides.items():
        if value is None:
            claims.pop(key, None)
        else:
            claims[key] = value
    return claims


def make_token(
    *,
    key: RSAPrivateKey = PRIVATE_A,
    kid: str | None = KID_A,
    alg: str = "RS256",
    headers: dict[str, Any] | None = None,
    **overrides: Any,
) -> str:
    hdrs: dict[str, Any] = {}
    if kid is not None:
        hdrs["kid"] = kid
    if headers:
        hdrs.update(headers)
    return jwt.encode(make_claims(**overrides), key, algorithm=alg, headers=hdrs)


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_unsigned_token(kid: str = KID_A, **overrides: Any) -> str:
    """alg=none token, built by hand (PyJWT refuses to create these with a kid)."""
    header = _b64url(json.dumps({"alg": "none", "typ": "JWT", "kid": kid}).encode())
    payload = _b64url(json.dumps(make_claims(**overrides)).encode())
    return f"{header}.{payload}."


def make_hs256_confusion_token(kid: str = KID_A, **overrides: Any) -> str:
    """HS256 token whose HMAC secret is the RSA *public* key (key-confusion attack)."""
    header = _b64url(json.dumps({"alg": "HS256", "typ": "JWT", "kid": kid}).encode())
    payload = _b64url(json.dumps(make_claims(**overrides)).encode())
    signing_input = f"{header}.{payload}".encode()
    sig = hmac.new(public_pem(PRIVATE_A), signing_input, hashlib.sha256).digest()
    return f"{header}.{payload}.{_b64url(sig)}"
