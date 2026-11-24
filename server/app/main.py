"""Spendge 服务端入口。"""

from flask import Flask, jsonify

from app.config import load_settings

settings = load_settings()


def create_app() -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False

    from app.devices import bp as devices_bp

    app.register_blueprint(devices_bp)

    @app.get("/health")
    def health():
        return jsonify(status="ok", env=settings.app_env)

    return app


app = create_app()
