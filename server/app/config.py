"""运行时配置：只从这里读环境变量，别的模块不要直接 os.getenv。"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_env: str
    log_level: str
    database_url: str
    device_token_ttl_days: int


def load_settings() -> Settings:
    return Settings(
        app_env=os.getenv("APP_ENV", "development"),
        log_level=os.getenv("LOG_LEVEL", "info"),
        database_url=os.getenv("DATABASE_URL", "sqlite:////home/ubuntu/sqlite/spendge.db"),
        device_token_ttl_days=int(os.getenv("DEVICE_TOKEN_TTL_DAYS", "90")),
    )
