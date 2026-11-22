"""运行时配置：只从这里读环境变量，别的模块不要直接 os.getenv。"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_env: str
    log_level: str
    llm_api_key: str | None


def load_settings() -> Settings:
    return Settings(
        app_env=os.getenv("APP_ENV", "development"),
        log_level=os.getenv("LOG_LEVEL", "info"),
        llm_api_key=os.getenv("LLM_API_KEY") or None,
    )
