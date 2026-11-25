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

import pytest  # noqa: E402

from app import cache  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_local_rate_limit():
    """测试都来自 127.0.0.1，逐个清掉本机 IP 计数，避免相互触发 429。"""
    try:
        cache.get_redis().delete("rl:ip:127.0.0.1")
    except Exception:  # noqa: BLE001
        pass
