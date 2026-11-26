"""Redis 访问层：设备读模型缓存 + 写队列（write-behind）。"""
from __future__ import annotations

import json

import redis

from app.config import load_settings

_settings = load_settings()
_client = None

DEVICE_KEY = "device:{id}"
STREAM_REGISTER = "stream:register"


def get_redis():
    global _client
    if _client is None:
        _client = redis.Redis.from_url(
            _settings.redis_url,
            socket_connect_timeout=0.3,
            socket_timeout=0.5,
            decode_responses=True,
        )
    return _client


def get_device(device_id: str) -> dict | None:
    raw = get_redis().get(DEVICE_KEY.format(id=device_id))
    return json.loads(raw) if raw else None


def set_device(device_id: str, state: dict, ttl_seconds: int) -> None:
    get_redis().set(DEVICE_KEY.format(id=device_id), json.dumps(state), ex=ttl_seconds)


def delete_device(device_id: str) -> None:
    get_redis().delete(DEVICE_KEY.format(id=device_id))


STREAM_MAXLEN = 10000  # 近似裁剪，防止流无限增长（约 3MB 上限）


def enqueue_register(device: dict, session: dict, seen_at: str) -> None:
    get_redis().xadd(
        STREAM_REGISTER,
        {"data": json.dumps({"device": device, "session": session, "seen_at": seen_at})},
        maxlen=STREAM_MAXLEN,
        approximate=True,
    )
