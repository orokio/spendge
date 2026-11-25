import uuid

import pytest

from app import cache
from app.db import SessionLocal
from app.main import create_app
from app.models import Device, Session
from app.writer import process_batch


@pytest.fixture
def client():
    app = create_app()
    app.config.update(TESTING=True)
    return app.test_client()


@pytest.fixture
def device_id():
    did = "test-" + uuid.uuid4().hex
    yield did
    try:
        cache.delete_device(did)
    except Exception:
        pass
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
    assert cache.get_device(device_id)["token_hash"]

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


def test_writer_persists_asynchronously(client, device_id):
    r = client.post("/v1/devices/register", json=_body(device_id))
    assert r.status_code == 200
    group = "test-" + uuid.uuid4().hex
    process_batch(batch=2000, block_ms=200, group=group, consumer="t")
    db = SessionLocal()
    try:
        assert db.get(Device, device_id) is not None
        assert db.query(Session).filter(Session.device_id == device_id).count() >= 1
    finally:
        db.close()

def _body_with_version(did, version):
    body = _body(did)
    body["categoriesVersion"] = version
    return body


def test_register_old_client_without_categories_version(client, device_id):
    r = client.post("/v1/devices/register", json=_body(device_id))
    assert r.status_code == 200
    j = r.get_json()
    assert "categories" not in j and "categoriesVersion" not in j


def test_register_client_version_0_gets_full_categories(client, device_id):
    from app import categories

    snapshot = categories.load_snapshot()
    assert snapshot["version"] >= 1, "分类未导入，先执行 python -m app.categories docs/categories-seed.json"

    r = client.post("/v1/devices/register", json=_body_with_version(device_id, 0))
    assert r.status_code == 200
    j = r.get_json()
    assert j["categoriesVersion"] == snapshot["version"]
    assert len(j["categories"]) == len(snapshot["items"]) >= 1
    item = j["categories"][0]
    assert set(item) == {
        "code", "name", "iconName", "colorHex", "kindRawValue",
        "domainRawValue", "scope", "sortOrder", "isArchived",
    }
    assert isinstance(item["sortOrder"], int) and isinstance(item["isArchived"], bool)


def test_register_same_version_returns_no_categories(client, device_id):
    from app import categories

    version = categories.load_snapshot()["version"]
    r = client.post("/v1/devices/register", json=_body_with_version(device_id, version))
    assert r.status_code == 200
    assert "categories" not in r.get_json()


def test_register_client_newer_version_returns_no_categories(client, device_id):
    from app import categories

    version = categories.load_snapshot()["version"] + 5
    r = client.post("/v1/devices/register", json=_body_with_version(device_id, version))
    assert r.status_code == 200
    assert "categories" not in r.get_json()


def test_register_survives_categories_failure(client, device_id, monkeypatch):
    from app import categories

    def boom():
        raise RuntimeError("redis down")

    monkeypatch.setattr(categories, "load_snapshot", boom)
    r = client.post("/v1/devices/register", json=_body_with_version(device_id, 0))
    assert r.status_code == 200
    j = r.get_json()
    assert j["deviceToken"] and "categories" not in j
