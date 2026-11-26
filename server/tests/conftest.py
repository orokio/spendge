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
def _reset_test_redis_state():
    """每个测试前清空测试流的待消费消息与限流计数。

    否则上一个测试留下的 register 事件会被下一个测试的新消费组从头重放，
    把 device_daily 的 register_count 累加多次。
    """
    try:
        r = cache.get_redis()
        r.delete(cache.STREAM_REGISTER)
        r.delete("rl:ip:127.0.0.1")
    except Exception:  # noqa: BLE001
        pass
