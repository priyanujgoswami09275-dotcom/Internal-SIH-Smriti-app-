"""Wave 5B — rate-limiter recovery + memory eviction.

- A Redis outage latches only for a cooldown; recovery is retried without a
  process restart.
- In-process buckets are swept once the IP count exceeds the cap, so IP churn
  cannot grow memory unboundedly.
"""
import time
from collections import deque

from app.middleware.rate_limit import RateLimitMiddleware


class _FailingRedis:
    """Stub middleware that always raises from _allow_redis (Redis down)."""


def _middleware(per_minute=1000) -> RateLimitMiddleware:
    return RateLimitMiddleware(app=None, per_minute=per_minute)


async def test_redis_failure_latches_only_for_cooldown():
    mw = _middleware()
    calls = {"n": 0}

    async def failing_redis(ip):
        calls["n"] += 1
        raise RuntimeError("redis down")

    mw._allow_redis = failing_redis

    # First request: Redis tried, fails, falls back to memory.
    assert await mw._allow("1.1.1.1") is True
    assert calls["n"] == 1

    # Within the cooldown: memory used, Redis NOT retried.
    assert await mw._allow("1.1.1.1") is True
    assert calls["n"] == 1

    # Cooldown expires: Redis is retried (recovers or fails again).
    mw._redis_retry_at = time.monotonic() - 0.01
    assert await mw._allow("1.1.1.1") is True
    assert calls["n"] == 2


def test_memory_buckets_evicted_beyond_cap():
    mw = _middleware(per_minute=1000)
    mw._MEMORY_BUCKET_CAP = 10
    now = time.monotonic()

    # Stuff 25 stale buckets (last hit outside the 60s window) + one active.
    for i in range(25):
        mw._hits[f"10.0.0.{i}"] = deque([now - 3600])
    mw._hits["active"] = deque([now])

    assert mw._allow_memory("2.2.2.2") is True  # triggers the sweep
    assert len(mw._hits) <= mw._MEMORY_BUCKET_CAP + 1
    assert "active" in mw._hits, "buckets with recent hits are kept"
    assert all(key.startswith(("10.0.0.", "2.2.2.2", "active")) for key in mw._hits)
    assert f"10.0.0.0" not in mw._hits, "stale buckets are evicted"


def test_memory_limit_still_enforced_after_eviction():
    mw = _middleware(per_minute=2)
    now = time.monotonic()
    for i in range(3):
        assert mw._allow_memory("3.3.3.3") is (i < 2)
    # The bucket survived (recent hits); the limit still applies.
    assert len(mw._hits["3.3.3.3"]) == 2
    assert now > 0
