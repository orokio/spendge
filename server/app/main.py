"""Spendge 服务端入口。

现在只有健康检查；云端解析接口按需在 app/ 下加 Blueprint 再注册进来。
"""

from flask import Flask, jsonify

from app.config import load_settings

settings = load_settings()


def create_app() -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False

    @app.get("/health")
    def health():
        return jsonify(status="ok", env=settings.app_env)

    return app


app = create_app()
