import pytest
from fastapi.testclient import TestClient
from api import app
from fitmatch.db import Database

client = TestClient(app)


def test_db_sync_session_lifecycle():
    db = Database()
    
    # 1. Create a test session
    session_id = db.create_sync_session(
        session_type="test_sync",
        trigger_source="pytest",
        metadata={"unit_test": True}
    )
    assert session_id is not None
    assert len(str(session_id)) > 0

    # 2. Record a crawl log with session_id
    db.record_crawl_log(
        store_id="test_store",
        category="running",
        items_found=42,
        duration_seconds=3.14,
        session_id=session_id
    )

    # 3. Update session
    updated = db.update_sync_session(
        session_id=session_id,
        status="completed",
        duration_seconds=10.5,
        total_items_processed=42,
        total_items_updated=40,
        total_price_drops=5,
        store_stats={"test_store": 42}
    )
    assert updated is True

    # 4. Fetch session
    sess = db.get_sync_session(session_id)
    assert sess is not None
    assert sess.get("status") == "completed"
    assert sess.get("total_items_processed") == 42
    assert sess.get("total_price_drops") == 5

    # 5. Fetch sessions list
    sessions = db.get_sync_sessions(limit=10, session_type="test_sync")
    assert isinstance(sessions, list)
    matching = [s for s in sessions if str(s.get("id")) == str(session_id)]
    assert len(matching) == 1

    # 6. Fetch latest session of type
    latest = db.get_latest_sync_session("test_sync")
    assert latest is not None
    assert str(latest.get("id")) == str(session_id)

    # 7. Delete session
    deleted = db.delete_sync_session(session_id)
    assert deleted is True
    assert db.get_sync_session(session_id) is None


def test_api_scheduler_sessions_endpoints():
    # Test GET /api/scheduler/status
    res_status = client.get("/api/scheduler/status")
    assert res_status.status_code == 200
    data = res_status.json()
    assert "is_running" in data
    assert "discovery" in data
    assert "refresh" in data

    # Test GET /api/scheduler/sessions
    res_sessions = client.get("/api/scheduler/sessions?limit=5")
    assert res_sessions.status_code == 200
    s_data = res_sessions.json()
    assert "total" in s_data
    assert "sessions" in s_data
    assert isinstance(s_data["sessions"], list)

    # Test DELETE /api/scheduler/sessions/{session_id}
    db = Database()
    test_sid = db.create_sync_session(session_type="test_del", trigger_source="pytest")
    del_res = client.delete(f"/api/scheduler/sessions/{test_sid}")
    assert del_res.status_code == 200
    assert del_res.json().get("status") == "success"
    assert db.get_sync_session(test_sid) is None
