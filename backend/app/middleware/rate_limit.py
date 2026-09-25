"""IP rate limiting — 100 req/min default (Phase 12).

Uses Redis when reachable so limits are shared across workers; falls back to an
in-process sliding window if Redis is down so a cache outage never takes the
API offline. Disabled outside production unless RATE_LIMIT_ENABLED=true.
"""
from __future__ import annotations

import logging
import time
from collections import defaultdict, deque
from typing import Deque, Dict, Optional

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.config import settings
from app.middleware.request_context import (
    bind_request_client_ip,
    reset_request_client_ip,
)

logger = logging.getLogger(__name__)

_SKIP_PATHS = {"/health", "/docs", "/redoc", "/openapi.json", "/api/v1/language/status"}


class RateLimitMiddleware(BaseHTTPMiddleware):
    # Redis is retried after this cooldown instead of latching off forever, so
    # a recovered cache instance is picked up without a process restart.
    _REDIS_RETRY_SECONDS = 30
    # In-process buckets beyond this count are swept for stale entries, so IP
    # churn cannot grow memory unboundedly.
    _MEMORY_BUCKET_CAP = 10_000

    def __init__(self, app, per_minute: Optional[int] = None):
        super().__init__(app)
        self.per_minute = per_minute or settings.RATE_LIMIT_PER_MINUTE
        self._hits: Dict[str, Deque[float]] = defaultdict(deque)
        self._redis = None
        self._redis_retry_at = 0.0

    async def dispatch(self, request: Request, call_next) -> Response:
        ip = request.client.host if request.client else None
        token = bind_request_client_ip(ip)
        try:
            if not settings.rate_limit_enabled:
                return await call_next(request)
            path = request.url.path
            if path in _SKIP_PATHS or path.endswith("/openapi.json"):
                return await call_next(request)

            allowed = await self._allow(ip or "unknown")
            if not allowed:
                return JSONResponse(
                    status_code=429,
                    content={"detail": f"Rate limit exceeded ({self.per_minute} requests/minute)"},
                    headers={"Retry-After": "60"},
                )
            return await call_next(request)
        finally:
            reset_request_client_ip(token)

    async def _allow(self, ip: str) -> bool:
        now = time.monotonic()
        if now >= self._redis_retry_at:
            try:
                return await self._allow_redis(ip)
            except Exception:  # noqa: BLE001 — degrade to memory
                self._redis_retry_at = now + self._REDIS_RETRY_SECONDS
                logger.warning("Redis rate-limit unavailable; using in-process limiter")
        return self._allow_memory(ip)

    async def _allow_redis(self, ip: str) -> bool:
        if self._redis is None:
            import redis.asyncio as redis

            self._redis = redis.from_url(settings.REDIS_URL, decode_responses=True)
        key = f"rl:{ip}"
        n = await self._redis.incr(key)
        if n == 1:
            await self._redis.expire(key, 60)
        return int(n) <= self.per_minute

    def _allow_memory(self, ip: str) -> bool:
        now = time.monotonic()
        window_start = now - 60
        if len(self._hits) > self._MEMORY_BUCKET_CAP:
            stale = [
                key for key, bucket in self._hits.items()
                if not bucket or bucket[-1] < window_start
            ]
            for key in stale:
                del self._hits[key]
        bucket = self._hits[ip]
        while bucket and bucket[0] < window_start:
            bucket.popleft()
        if len(bucket) >= self.per_minute:
            return False
        bucket.append(now)
        return True
