"""Write-behind worker：消费 Redis Stream，批量 upsert 到 SQLite。

独立进程运行（systemd），与 gunicorn 解耦；接口线程只写 Redis，不写 DB。
"""
from __future__ import annotations

import json
import logging
import time

import redis
from sqlalchemy import text

from app.cache import STREAM_REGISTER
from app.config import load_settings
from app.db import SessionLocal

GROUP = "writer"
CONSUMER = "writer-1"

_settings = load_settings()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("writer")
_client = None

_DEVICE_SQL = text(
    """
    INSERT INTO devices (id, secret_hash, app_version, build, platform, account_id, created_at, last_seen_at)
    VALUES (:id, :secret_hash, :app_version, :build, :platform, :account_id, :created_at, :last_seen_at)
    ON CONFLICT(id) DO UPDATE SET
        secret_hash = excluded.secret_hash,
        app_version = excluded.app_version,
        build = excluded.build,
        platform = excluded.platform,
        last_seen_at = excluded.last_seen_at
    """
)

_SESSION_SQL = text(
    """
    INSERT INTO sessions (token_hash, account_id, device_id, expires_at, created_at)
    VALUES (:token_hash, :account_id, :device_id, :expires_at, :created_at)
    ON CONFLICT(token_hash) DO UPDATE SET expires_at = excluded.expires_at
    """
)


def _writer_redis():
    """writer 用独立连接：阻塞读不能用很短的 socket_timeout。"""
    global _client
    if _client is None:
        _client = redis.Redis.from_url(_settings.redis_url, decode_responses=True)
    return _client


def ensure_group(r, group: str = GROUP) -> None:
    try:
        r.xgroup_create(STREAM_REGISTER, group, id="0", mkstream=True)
    except Exception as exc:  # noqa: BLE001
        if "BUSYGROUP" not in str(exc):
            raise


def _apply(db, evt: dict) -> None:
    db.execute(_DEVICE_SQL, evt["device"])
    db.execute(_SESSION_SQL, evt["session"])


def process_batch(batch: int = 200, block_ms: int = 2000, group: str = GROUP, consumer: str = CONSUMER) -> int:
    r = _writer_redis()
    ensure_group(r, group)
    resp = r.xreadgroup(group, consumer, {STREAM_REGISTER: ">"}, count=batch, block=block_ms)
    if not resp:
        return 0
    processed = 0
    for _stream, entries in resp:
        ids = [mid for mid, _ in entries]
        db = SessionLocal()
        try:
            for _mid, fields in entries:
                _apply(db, json.loads(fields["data"]))
            db.commit()
        except Exception:
            db.rollback()
            logger.exception("batch failed, will retry")
            return 0
        finally:
            db.close()
        if ids:
            r.xack(STREAM_REGISTER, group, *ids)
            processed += len(ids)
    return processed


def main() -> None:
    ensure_group(_writer_redis(), GROUP)
    logger.info("writer started")
    while True:
        try:
            process_batch()
        except Exception:
            logger.exception("writer loop error")
            time.sleep(1)


if __name__ == "__main__":
    main()
