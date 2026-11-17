import json
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient

import api as fitmatch_api
from fitmatch.smart_search import OpenRouterParser, VisualSearchResult


def _mock_openrouter_response(payload_dict: dict):
    body = {
        "choices": [
            {
                "message": {
                    "content": json.dumps(payload_dict)
                }
            }
        ]
    }
    resp = MagicMock()
    resp.status = 200
    resp.read.return_value = json.dumps(body).encode("utf-8")
    resp.__enter__ = lambda self: self
    resp.__exit__ = lambda self, exc_type, exc, tb: False
    return resp


def test_analyze_image_parses_sport_product_and_strips_data_url():
    fake_json = {
        "is_sport_product": True,
        "recognized_model": "Hoka Clifton 9",
        "brand": "Hoka",
        "category": "Running",
        "color": "Blu",
        "search_query": "Hoka Clifton 9",
        "confidence": "high",
        "alternatives": ["Hoka Clifton 9", "Hoka Bondi 8", "Hoka Mach 6"],
        "note": "Scarpa da running su strada leggera e molto ammortizzata.",
    }
    with patch("urllib.request.urlopen", return_value=_mock_openrouter_response(fake_json)) as mock_open:
        result = OpenRouterParser.analyze_image(
            image_base64="data:image/jpeg;base64,/9j/4AAQSkZJRg==",
            api_key="test-key",
        )

    assert result is not None
    assert result.is_sport_product is True
    assert result.recognized_model == "Hoka Clifton 9"
    assert result.brand == "Hoka"
    assert result.search_query == "Hoka Clifton 9"
    assert result.confidence == "high"
    # Duplicate search_query should be filtered from alternatives
    assert result.alternatives == ["Hoka Bondi 8", "Hoka Mach 6"]

    req_arg = mock_open.call_args[0][0]
    sent_payload = json.loads(req_arg.data.decode("utf-8"))
    image_url = sent_payload["messages"][1]["content"][1]["image_url"]["url"]
    assert image_url == "data:image/jpeg;base64,/9j/4AAQSkZJRg=="


def test_analyze_image_handles_non_sport_product():
    fake_json = {
        "is_sport_product": False,
        "recognized_model": "Oggetto non sportivo",
        "brand": None,
        "category": "Accessori",
        "color": None,
        "search_query": "",
        "confidence": "high",
        "alternatives": [],
        "note": "L'immagine non sembra mostrare articoli sportivi.",
    }
    with patch("urllib.request.urlopen", return_value=_mock_openrouter_response(fake_json)):
        result = OpenRouterParser.analyze_image(image_base64="YWJj", api_key="test-key")

    assert result is not None
    assert result.is_sport_product is False
    assert "non sembra" in (result.note or "").lower()


def test_visual_search_endpoint_success_and_validation():
    client = TestClient(fitmatch_api.app)

    empty_resp = client.post("/api/search/visual", json={"image_base64": "   "})
    assert empty_resp.status_code == 400

    mock_result = VisualSearchResult(
        is_sport_product=True,
        recognized_model="Nike Pegasus 41",
        brand="Nike",
        category="Running",
        color="Nero",
        search_query="Nike Pegasus 41",
        confidence="high",
        alternatives=["Nike Pegasus 40"],
        note="Scarpa da corsa su strada.",
    )
    with patch("fitmatch.smart_search.OPENROUTER_API_KEY", "test-key"), \
         patch("fitmatch.smart_search.OpenRouterParser.analyze_image", return_value=mock_result), \
         patch.object(fitmatch_api.db, "search_smart", return_value=[{"canonical_name": "Nike Pegasus 41"}, {"canonical_name": "Nike Pegasus 41 Gore-Tex"}]), \
         patch.object(fitmatch_api.db, "use_supabase", True), \
         patch.object(fitmatch_api.db.supabase, "upload_chat_image", return_value="https://goopfdvnqhdmsoutkldp.supabase.co/storage/v1/object/public/chat-images/dev/abc.jpg"):
        ok_resp = client.post("/api/search/visual", json={"image_base64": "YWJj", "mime_type": "image/jpeg", "device_id": "dev"})

    assert ok_resp.status_code == 200
    data = ok_resp.json()
    assert data["is_sport_product"] is True
    assert data["recognized_model"] == "Nike Pegasus 41"
    assert data["catalog_matches_count"] == 2
    assert data["uploaded_image_url"] == "https://goopfdvnqhdmsoutkldp.supabase.co/storage/v1/object/public/chat-images/dev/abc.jpg"


def test_persist_smart_search_turn_attaches_user_image_url():
    sample_payload = {
        "search_mode": "deep_dive",
        "is_deep_dive": True,
        "conversational_header": "Ho cercato Nike Pegasus 41",
        "conversational_summary": "Ecco i modelli trovati.",
        "results": [],
        "intent": {"raw_query": "Nike Pegasus 41"},
        "chips": [],
    }
    captured = {}

    def _fake_save(**kwargs):
        captured.update(kwargs)
        return {"session_id": "11111111-1111-1111-1111-111111111111", "turn_id": "22222222-2222-2222-2222-222222222222"}

    img_url = "https://goopfdvnqhdmsoutkldp.supabase.co/storage/v1/object/public/chat-images/dev/abc.jpg"
    with patch.object(fitmatch_api.db, "save_chat_turn", side_effect=_fake_save):
        out = fitmatch_api._persist_smart_search_turn(
            sample_payload,
            query="Nike Pegasus 41",
            session_id="11111111-1111-1111-1111-111111111111",
            device_id="dev",
            user_id=None,
            is_follow_up=False,
            user_image_url=img_url,
        )

    assert captured["user_image_url"] == img_url
    assert out["user_image_url"] == img_url
    assert "user_image_url" not in sample_payload
