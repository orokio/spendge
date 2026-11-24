"""Redis 限流；Redis 不可用时降级放行。"""
from __future__ import annotations

import redis

from app.config import load_settings

_settings = load_settings()
_disabled = False
_client = None


def _get_client():
    global _client
    if _client is None:
        _client = redis.Redis.from_url(
            _settings.redis_url,
            socket_connect_timeout=0.2,
            socket_timeout=0.2,
        )
    return _client


def allow(key: str, limit: int, window_seconds: int) -> bool:
    """固定窗口计数；返回 True 表示放行。Redis 不可用时放行。"""
    global _disabled
    if _disabled:
        return True
    try:
        client = _get_client()
        count = client.incr(key)
        if count == 1:
            client.expire(key, window_seconds)
        return count <= limit
    except Exception:  # noqa: BLE001
        _disabled = True
        return True
