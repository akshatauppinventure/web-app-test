"""In-memory JWKS cache with rate-limited refresh (ADR-0011 §3).

Keys are fetched lazily from Keycloak over the internal network and cached. A token with
an unknown ``kid`` triggers one refresh, at most once per ``min_refresh_interval`` seconds,
so a flood of bogus ``kid`` values cannot turn the API into a JWKS-fetching machine.
"""

import asyncio
import time
from collections.abc import Callable

import httpx
import structlog
from jwt import PyJWK, PyJWKSet

log = structlog.get_logger("app.auth.jwks")


class JWKSUnavailableError(Exception):
    """The key set could not be loaded and nothing is cached."""


class JWKSClient:
    def __init__(
        self,
        url: str,
        http: httpx.AsyncClient,
        *,
        min_refresh_interval: float = 60.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._url = url
        self._http = http
        self._min_refresh_interval = min_refresh_interval
        self._clock = clock
        self._keys: dict[str, PyJWK] = {}
        self._loaded = False
        self._last_kid_refresh: float | None = None
        self._lock = asyncio.Lock()

    async def get_key(self, kid: str) -> PyJWK | None:
        """Return the key for ``kid``; refresh (rate-limited) when it is unknown."""
        if not self._loaded:
            await self._refresh(unknown_kid=False)
        key = self._keys.get(kid)
        if key is None:
            await self._refresh(unknown_kid=True)
            key = self._keys.get(kid)
        return key

    async def _refresh(self, *, unknown_kid: bool) -> None:
        async with self._lock:
            now = self._clock()
            if unknown_kid:
                last = self._last_kid_refresh
                if last is not None and now - last < self._min_refresh_interval:
                    return
                self._last_kid_refresh = now
            elif self._loaded:
                return  # another request loaded the keys while we waited for the lock
            try:
                resp = await self._http.get(self._url, timeout=5.0)
                resp.raise_for_status()
                key_set = PyJWKSet.from_dict(resp.json())
            except Exception as exc:
                log.warning("jwks_refresh_failed", error=type(exc).__name__)
                if not self._loaded:
                    raise JWKSUnavailableError from exc
                return
            self._keys = {k.key_id: k for k in key_set.keys if k.key_id}
            self._loaded = True
            log.info("jwks_refreshed", kids=sorted(self._keys))
