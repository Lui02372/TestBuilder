from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


def test_chat_returns_ollama_response():
    fake_resp = MagicMock()
    fake_resp.raise_for_status.return_value = None
    fake_resp.json.return_value = {"response": "안녕하세요"}

    with patch("main.httpx.AsyncClient") as mock_client_cls:
        mock_client = mock_client_cls.return_value.__aenter__.return_value
        mock_client.post = AsyncMock(return_value=fake_resp)

        resp = client.post("/api/chat", json={"prompt": "hi"})

    assert resp.status_code == 200
    assert resp.json()["response"] == "안녕하세요"


def test_chat_requires_prompt():
    resp = client.post("/api/chat", json={})
    assert resp.status_code == 422
