from app.main import app


def test_health() -> None:
    response = app.test_client().get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"
