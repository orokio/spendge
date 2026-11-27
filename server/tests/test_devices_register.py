import uuid

import pytest

from app.db import SessionLocal
from app.main import create_app
from app.models import Device, DeviceDaily, Session


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
        db.query(DeviceDaily).filter(DeviceDaily.device_id == did).delete()
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

    db = SessionLocal()
    try:
        assert db.query(Session).filter(Session.device_id == device_id).count() == 1
    finally:
        db.close()

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
    assert snapshot["version"] >= 1, "分类未导入，先执行 python -m app.categories server/categories-seed.json"

    r = client.post("/v1/devices/register", json=_body_with_version(device_id, 0))
    assert r.status_code == 200
    j = r.get_json()
    assert j["categoriesVersion"] == snapshot["version"]
    assert len(j["categories"]) == len(snapshot["items"]) >= 1
    item = j["categories"][0]
    assert set(item) == {
        "code", "name", "iconName", "colorHex", "kindRawValue",
        "domainRawValue", "scope", "sortOrder", "isArchived", "goalKinds",
    }
    assert isinstance(item["sortOrder"], int) and isinstance(item["isArchived"], bool)
    assert all(isinstance(c["goalKinds"], list) for c in j["categories"])


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
        raise RuntimeError("db down")

    monkeypatch.setattr(categories, "load_snapshot", boom)
    r = client.post("/v1/devices/register", json=_body_with_version(device_id, 0))
    assert r.status_code == 200
    j = r.get_json()
    assert j["deviceToken"] and "categories" not in j

def test_category_snapshot_exists_for_current_version():
    from app import categories

    snapshot = categories.load_snapshot()
    if snapshot["version"] == 0:
        pytest.skip("分类未导入")
    record = categories.get_version(snapshot["version"])
    assert record is not None, "当前版本缺少快照"
    assert len(record["payload"]) == len(snapshot["items"])

def test_goal_kinds_normalization():
    from app.categories import _normalize_goal_kinds

    assert _normalize_goal_kinds("x", ["shareCap", "budget"]) == "budget,shareCap"
    assert _normalize_goal_kinds("x", "countLimit,budget") == "countLimit,budget"
    assert _normalize_goal_kinds("x", ["budget", "budget"]) == "budget"
    assert _normalize_goal_kinds("x", []) == ""
    assert _normalize_goal_kinds("x", None) == ""
    with pytest.raises(ValueError):
        _normalize_goal_kinds("x", ["budget", "bogus"])

def test_device_daily_counts_registers(client, device_id):
    assert client.post("/v1/devices/register", json=_body(device_id)).status_code == 200
    assert client.post("/v1/devices/register", json=_body(device_id)).status_code == 200

    db = SessionLocal()
    try:
        rows = db.query(DeviceDaily).filter(DeviceDaily.device_id == device_id).all()
        assert len(rows) == 1, "同一天应只有一行"
        row = rows[0]
        assert row.register_count == 2
        assert row.first_seen_at <= row.last_seen_at
        assert row.build == "1"
    finally:
        db.close()


def test_stats_compute_within_sqlite():
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker

    from app.db import Base
    from app.stats import compute

    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    S = sessionmaker(bind=engine)
    s = S()
    try:
        day = "2026-11-26"
        seen = "2026-11-26T01:00:00Z"  # 落在 CST 11-26 的窗口内
        s.add(Device(id="AAAAAAAA-1111-2222-3333-444444444444", secret_hash="h", created_at=seen, last_seen_at=seen))
        s.add(Device(id="test-bad", secret_hash="h", created_at=seen, last_seen_at=seen))
        s.add(DeviceDaily(device_id="AAAAAAAA-1111-2222-3333-444444444444", stat_date=day,
                          first_seen_at=seen, last_seen_at=seen, register_count=2, build="8"))
        # B 当天新增但还没有 device_daily 行：仍应计入活跃（活跃 ⊇ 新增）
        s.add(Device(id="BBBBBBBB-1111-2222-3333-444444444444", secret_hash="h",
                     build="7", created_at=seen, last_seen_at=seen))
        s.add(DeviceDaily(device_id="test-bad", stat_date=day,
                          first_seen_at=seen, last_seen_at=seen, register_count=1, build="8"))
        s.commit()

        result = compute(day, session=s)
        assert result["active"] == 2
        assert result["new"] == 2
        assert {b["build"]: (b["new"], b["active"]) for b in result["builds"]} == {
            "7": (1, 1),
            "8": (1, 1),
        }
    finally:
        s.close()
        engine.dispose()