"""设备登记与设备 token 签发（register 直接写 SQLite，短事务）。"""
from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request
from sqlalchemy import select, text
from sqlalchemy.exc import OperationalError

from app import categories
from app.config import load_settings
from app.db import SessionLocal
from app.models import Device, Session
from app.stats import date_cst

bp = Blueprint("devices", __name__)
_settings = load_settings()
logger = logging.getLogger(__name__)

_DAILY_SQL = text(
    """
    INSERT INTO device_daily (device_id, stat_date, first_seen_at, last_seen_at, register_count, app_version, build)
    VALUES (:device_id, :stat_date, :seen_at, :seen_at, 1, :app_version, :build)
    ON CONFLICT(device_id, stat_date) DO UPDATE SET
        first_seen_at = CASE WHEN excluded.first_seen_at < first_seen_at
                             THEN excluded.first_seen_at ELSE first_seen_at END,
        last_seen_at  = CASE WHEN excluded.last_seen_at > last_seen_at
                             THEN excluded.last_seen_at ELSE last_seen_at END,
        register_count = register_count + 1,
        app_version = excluded.app_version,
        build = excluded.build
    """
)


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _error(code: str, message: str, status: int):
    return jsonify({"code": code, "message": message}), status


def _touch_daily(db, device_id: str, seen_at: str, app_version, build) -> None:
    db.execute(
        _DAILY_SQL,
        {
            "device_id": device_id,
            "stat_date": date_cst(seen_at),
            "seen_at": seen_at,
            "app_version": app_version,
            "build": build,
        },
    )


def _client_categories_version(raw) -> int | None:
    """客户端上报的分类版本；缺省/非法一律视为未上报（老客户端）。"""
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str) and raw.strip().lstrip("-").isdigit():
        return int(raw.strip())
    return None


def _attach_categories(payload: dict, raw_version) -> dict:
    """仅当服务端版本高于客户端版本时附带全量分类；任何异常都不影响设备登记。"""
    client_version = _client_categories_version(raw_version)
    if client_version is None:
        return payload
    try:
        snapshot = categories.load_snapshot()
    except Exception:  # noqa: BLE001
        logger.exception("categories load failed; register continues without categories")
        return payload
    if snapshot.get("version", 0) > client_version:
        payload["categoriesVersion"] = snapshot["version"]
        payload["categories"] = snapshot.get("items", [])
    return payload


@bp.post("/v1/devices/register")
def register():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return _error("invalid_request", "请求体必须是 JSON", 400)

    device_id = (data.get("deviceId") or "").strip()
    device_secret = data.get("deviceSecret") or ""
    if not device_id or not device_secret:
        return _error("invalid_request", "deviceId 与 deviceSecret 必填", 400)

    now = datetime.now(timezone.utc)
    now_iso = _iso(now)
    expires_iso = _iso(now + timedelta(days=_settings.device_token_ttl_days))
    secret_hash = _sha256(device_secret)
    app_version = data.get("appVersion")
    build = data.get("build")
    platform = data.get("platform")

    db = SessionLocal()
    try:
        device = db.get(Device, device_id)

        if device is None:
            token = secrets.token_urlsafe(32)
            db.add(
                Device(
                    id=device_id,
                    secret_hash=secret_hash,
                    app_version=app_version,
                    build=build,
                    platform=platform,
                    created_at=now_iso,
                    last_seen_at=now_iso,
                )
            )
            db.add(
                Session(
                    token_hash=_sha256(token),
                    device_id=device_id,
                    expires_at=expires_iso,
                    created_at=now_iso,
                )
            )
            _touch_daily(db, device_id, now_iso, app_version, build)
            db.commit()
            return jsonify(
                _attach_categories(
                    {"deviceToken": token, "expiresAt": expires_iso},
                    data.get("categoriesVersion"),
                )
            ), 200

        if device.secret_hash != secret_hash:
            db.rollback()
            return _error("secret_mismatch", "deviceSecret 不匹配", 403)

        device.last_seen_at = now_iso
        if app_version:
            device.app_version = app_version
        if build:
            device.build = build
        if platform:
            device.platform = platform

        session = db.execute(
            select(Session)
            .where(Session.device_id == device_id, Session.expires_at > now_iso)
            .order_by(Session.expires_at.desc())
        ).scalars().first()

        token = None
        if session is not None:
            session.expires_at = expires_iso
        else:
            token = secrets.token_urlsafe(32)
            db.add(
                Session(
                    token_hash=_sha256(token),
                    device_id=device_id,
                    expires_at=expires_iso,
                    created_at=now_iso,
                )
            )

        _touch_daily(db, device_id, now_iso, app_version or device.app_version, build or device.build)
        db.commit()

        payload = {"expiresAt": expires_iso}
        if token:
            payload["deviceToken"] = token
        return jsonify(_attach_categories(payload, data.get("categoriesVersion"))), 200
    except OperationalError:
        db.rollback()
        logger.warning("register: database busy")
        return _error("service_unavailable", "服务暂不可用", 503)
    except Exception:  # noqa: BLE001
        db.rollback()
        logger.exception("register failed")
        return _error("service_unavailable", "服务暂不可用", 503)
    finally:
        db.close()
