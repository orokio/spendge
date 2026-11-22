"""Spendge 服务端入口。

现在只有健康检查；云端解析接口按需在 app/ 下新建 router 再挂上来。
"""

from fastapi import FastAPI

from app.config import load_settings

settings = load_settings()
app = FastAPI(title="spendge-server", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "env": settings.app_env}
