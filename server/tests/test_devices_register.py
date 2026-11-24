import uuid

import pytest

from app.db import SessionLocal
from app.main import create_app
from app.models import Device, Session


@pytest.fixture
def client():
    app = create_app()
    app.config.update(TESTING=True)
    return app.test_client()


@pytest.fixture
def device_id():
    did = "test-" + uuid.uuid4().hex
    yield did
    db = SessionLocal()
    try:
        db.query(Session).filter(Session.device_id == did).delete()
        db.query(Device).filter(Device.id == did).delete()
        db.commit()
    finally:
        db.close()


def _body(did, secret="c2VjcmV0"):
    return {"deviceId": did, "deviceSecret": secret, "appVersion": "1.0", "build": "1", "platform": "ios"}


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_register_first_then_renew(client, device_id):
    r1 = client.post("/v1/devices/register", json=_body(device_id))
    assert r1.status_code == 200
    j1 = r1.get_json()
    assert j1["deviceToken"] and j1["expiresAt"]

    r2 = client.post("/v1/devices/register", json=_body(device_id))
    assert r2.status_code == 200
    j2 = r2.get_json()
    assert "expiresAt" in j2 and "deviceToken" not in j2


def test_register_secret_mismatch(client, device_id):
    assert client.post("/v1/devices/register", json=_body(device_id)).status_code == 200
    r = client.post("/v1/devices/register", json=_body(device_id, secret="d3Jvbmc="))
    assert r.status_code == 403
    assert r.get_json()["code"] == "secret_mismatch"


def test_register_missing_fields(client, device_id):
    r = client.post("/v1/devices/register", json={"deviceId": device_id})
    assert r.status_code == 400
    assert r.get_json()["code"] == "invalid_request"
