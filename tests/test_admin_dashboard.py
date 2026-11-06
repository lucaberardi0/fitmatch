from fastapi.testclient import TestClient
from api import app
from fitmatch.admin_dashboard import get_admin_overview, render_admin_html
from fitmatch.db import Database
from fitmatch.scheduler import SyncScheduler

client = TestClient(app)


def test_admin_overview_data():
    db = Database()
    sched = SyncScheduler.get_instance(db=db)
    overview = get_admin_overview(db, sched)

    assert "scheduler" in overview
    assert "catalog" in overview
    assert "store_health" in overview
    assert "recent_sessions" in overview
    assert "size_metrics" in overview
    assert isinstance(overview["store_health"], list)
    assert len(overview["store_health"]) > 0


def test_admin_html_rendering():
    html = render_admin_html()
    assert isinstance(html, str)
    assert "FitMatch" in html
    assert "Control Center" in html
    assert "triggerDiscovery" in html
    assert "store-health-tbody" in html


def test_admin_api_endpoints():
    # Test GET /admin HTML page
    res_html = client.get("/admin")
    assert res_html.status_code == 200
    assert "text/html" in res_html.headers.get("content-type", "")
    assert "FitMatch" in res_html.text

    # Test GET /dashboard alias
    res_dash = client.get("/dashboard")
    assert res_dash.status_code == 200

    # Test GET /api/admin/overview JSON endpoint
    res_json = client.get("/api/admin/overview")
    assert res_json.status_code == 200
    data = res_json.json()
    assert "scheduler" in data
    assert "store_health" in data
    assert "size_metrics" in data
