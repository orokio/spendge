import os
import pathlib

_env = pathlib.Path(__file__).resolve().parent.parent / ".env"
if _env.exists():
    for _line in _env.read_text().splitlines():
        _line = _line.strip()
        if not _line or _line.startswith("#") or "=" not in _line:
            continue
        _k, _v = _line.split("=", 1)
        os.environ.setdefault(_k, _v)

# 测试隔离：Redis 切到独立 DB（15），避免测试的消费组/限流键污染生产流
TEST_REDIS_DB = "15"
_redis_url = os.environ.get("REDIS_URL", "")
if _redis_url:
    _base, _sep, _db = _redis_url.rpartition("/")
    if _sep and _db.isdigit() and _base:
        os.environ["REDIS_URL"] = f"{_base}/{TEST_REDIS_DB}"

import pytest  # noqa: E402

from app import cache  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _clean_test_redis_db():
    """测试库每次跑前清空（仅 DB 15，不碰生产 DB 0）。"""
    try:
        cache.get_redis().flushdb()
    except Exception:  # noqa: BLE001
        pass


@pytest.fixture(autouse=True)
def _reset_local_rate_limit():
    """测试都来自 127.0.0.1，逐个清掉本机 IP 计数，避免相互触发 429。"""
    try:
        cache.get_redis().delete("rl:ip:127.0.0.1")
    except Exception:  # noqa: BLE001
        pass
