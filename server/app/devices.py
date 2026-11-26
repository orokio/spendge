"""设备登记与设备 token 签发（write-behind：接口只写 Redis，不写 DB）。"""
from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request
from sqlalchemy import select

from app import cache, categories
from app.config import load_settings
from app.db import SessionLocal
from app.models import Device, Session
from app.rate_limit import allow

bp = Blueprint("devices", __name__)
_settings = load_settings()
logger = logging.getLogger(__name__)

_STATE_TTL = (_settings.device_token_ttl_days + 1) * 86400


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _error(code: str, message: str, status: int):
    return jsonify({"code": code, "message": message}), status


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


def _load_state_from_db(device_id: str) -> dict | None:
    """缓存未命中时只读回源（不修改数据库）。"""
    db = SessionLocal()
    try:
        device = db.get(Device, device_id)
        if device is None:
            return None
        now_iso = _iso(datetime.now(timezone.utc))
        session = db.execute(
            select(Session)
            .where(Session.device_id == device_id, Session.expires_at > now_iso)
            .order_by(Session.expires_at.desc())
        ).scalars().first()
        return {
            "secret_hash": device.secret_hash,
            "token_hash": session.token_hash if session else None,
            "expires_at": session.expires_at if session else None,
            "app_version": device.app_version,
            "build": device.build,
            "platform": device.platform,
            "account_id": device.account_id,
            "created_at": device.created_at,
            "last_seen_at": device.last_seen_at,
        }
    finally:
        db.close()


def _device_row(device_id: str, state: dict) -> dict:
    return {
        "id": device_id,
        "secret_hash": state["secret_hash"],
        "app_version": state.get("app_version"),
        "build": state.get("build"),
        "platform": state.get("platform"),
        "account_id": state.get("account_id"),
        "created_at": state["created_at"],
        "last_seen_at": state["last_seen_at"],
    }


def _session_row(device_id: str, state: dict) -> dict:
    return {
        "token_hash": state["token_hash"],
        "account_id": state.get("account_id"),
        "device_id": device_id,
        "expires_at": state["expires_at"],
        "created_at": state["created_at"],
    }


@bp.post("/v1/devices/register")
def register():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return _error("invalid_request", "请求体必须是 JSON", 400)

    device_id = (data.get("deviceId") or "").strip()
    device_secret = data.get("deviceSecret") or ""
    if not device_id or not device_secret:
        return _error("invalid_request", "deviceId 与 deviceSecret 必填", 400)

    try:
        cache.get_redis().ping()
    except Exception:  # noqa: BLE001
        return _error("service_unavailable", "服务暂不可用", 503)

    ip = request.headers.get("X-Real-IP") or (request.remote_addr or "unknown")
    if not allow(f"rl:ip:{ip}", 10, 60) or not allow(f"rl:dev:{device_id}", 5, 60):
        return _error("rate_limited", "请求过于频繁", 429)

    now = datetime.now(timezone.utc)
    now_iso = _iso(now)
    expires_iso = _iso(now + timedelta(days=_settings.device_token_ttl_days))
    secret_hash = _sha256(device_secret)

    try:
        state = cache.get_device(device_id)
        if state is None:
            state = _load_state_from_db(device_id)
            if state is not None:
                cache.set_device(device_id, state, _STATE_TTL)

        if state is None:
            token = secrets.token_urlsafe(32)
            state = {
                "secret_hash": secret_hash,
                "token_hash": _sha256(token),
                "expires_at": expires_iso,
                "app_version": data.get("appVersion"),
                "build": data.get("build"),
                "platform": data.get("platform"),
                "account_id": None,
                "created_at": now_iso,
                "last_seen_at": now_iso,
            }
            cache.set_device(device_id, state, _STATE_TTL)
            cache.enqueue_register(_device_row(device_id, state), _session_row(device_id, state), now_iso)
            return jsonify(_attach_categories({"deviceToken": token, "expiresAt": expires_iso}, data.get("categoriesVersion"))), 200

        if state["secret_hash"] != secret_hash:
            return _error("secret_mismatch", "deviceSecret 不匹配", 403)

        state["last_seen_at"] = now_iso
        if data.get("appVersion"):
            state["app_version"] = data["appVersion"]
        if data.get("build"):
            state["build"] = data["build"]
        if data.get("platform"):
            state["platform"] = data["platform"]

        token_valid = bool(state.get("token_hash")) and bool(state.get("expires_at")) and state["expires_at"] > now_iso
        if token_valid:
            state["expires_at"] = expires_iso
            cache.set_device(device_id, state, _STATE_TTL)
            cache.enqueue_register(_device_row(device_id, state), _session_row(device_id, state), now_iso)
            return jsonify(_attach_categories({"expiresAt": expires_iso}, data.get("categoriesVersion"))), 200

        token = secrets.token_urlsafe(32)
        state["token_hash"] = _sha256(token)
        state["expires_at"] = expires_iso
        cache.set_device(device_id, state, _STATE_TTL)
        cache.enqueue_register(_device_row(device_id, state), _session_row(device_id, state), now_iso)
        return jsonify(_attach_categories({"deviceToken": token, "expiresAt": expires_iso}, data.get("categoriesVersion"))), 200
    except Exception:  # noqa: BLE001
        return _error("service_unavailable", "服务暂不可用", 503)
