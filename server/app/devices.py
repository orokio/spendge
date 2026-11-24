"""设备登记与设备 token 签发（见 docs/api-contract.md §4.2）。"""
from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request
from sqlalchemy import select

from app.config import load_settings
from app.db import SessionLocal
from app.models import Device, Session
from app.rate_limit import allow

bp = Blueprint("devices", __name__)
_settings = load_settings()


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _error(code: str, message: str, status: int):
    return jsonify({"code": code, "message": message}), status


@bp.post("/v1/devices/register")
def register():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return _error("invalid_request", "请求体必须是 JSON", 400)

    device_id = (data.get("deviceId") or "").strip()
    device_secret = data.get("deviceSecret") or ""
    if not device_id or not device_secret:
        return _error("invalid_request", "deviceId 与 deviceSecret 必填", 400)

    ip = request.headers.get("X-Real-IP") or (request.remote_addr or "unknown")
    if not allow(f"rl:ip:{ip}", 10, 60) or not allow(f"rl:dev:{device_id}", 5, 60):
        return _error("rate_limited", "请求过于频繁", 429)

    now = datetime.now(timezone.utc)
    now_iso = _iso(now)
    expires_iso = _iso(now + timedelta(days=_settings.device_token_ttl_days))
    secret_hash = _sha256(device_secret)

    db = SessionLocal()
    try:
        device = db.get(Device, device_id)

        if device is None:
            token = secrets.token_urlsafe(32)
            db.add(Device(
                id=device_id,
                secret_hash=secret_hash,
                app_version=data.get("appVersion"),
                build=data.get("build"),
                platform=data.get("platform"),
                created_at=now_iso,
                last_seen_at=now_iso,
            ))
            db.add(Session(
                token_hash=_sha256(token),
                device_id=device_id,
                expires_at=expires_iso,
                created_at=now_iso,
            ))
            db.commit()
            return jsonify({"deviceToken": token, "expiresAt": expires_iso}), 200

        if device.secret_hash != secret_hash:
            return _error("secret_mismatch", "deviceSecret 不匹配", 403)

        device.last_seen_at = now_iso
        if data.get("appVersion"):
            device.app_version = data["appVersion"]
        if data.get("build"):
            device.build = data["build"]
        if data.get("platform"):
            device.platform = data["platform"]

        session = None
        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            session = db.get(Session, _sha256(auth[7:]))
            if session is not None and session.device_id != device_id:
                session = None
        if session is None:
            session = db.execute(
                select(Session)
                .where(Session.device_id == device_id, Session.expires_at > now_iso)
                .order_by(Session.expires_at.desc())
            ).scalars().first()

        if session is not None and session.expires_at > now_iso:
            session.expires_at = expires_iso
            db.commit()
            return jsonify({"expiresAt": expires_iso}), 200

        token = secrets.token_urlsafe(32)
        db.add(Session(
            token_hash=_sha256(token),
            device_id=device_id,
            expires_at=expires_iso,
            created_at=now_iso,
        ))
        db.commit()
        return jsonify({"deviceToken": token, "expiresAt": expires_iso}), 200
    finally:
        db.close()
