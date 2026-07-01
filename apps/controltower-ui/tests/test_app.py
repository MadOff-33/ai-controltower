import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
APP_PATH = ROOT / "apps" / "controltower-ui" / "app.py"


def test_state_endpoint_exposes_project_paths(client):
    state = client.get("/api/state")
    assert state.status_code == 200
    payload = state.get_json()
    assert "audit_project_path" in payload
    assert "creation_parent_path" in payload


def test_report_endpoint_renders_markdown_table(client):
    workspace = ROOT / "audits" / "20990101-000000_ui_report_fixture"
    report_dir = workspace / "reports"
    report_path = report_dir / "ui_report.md"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path.write_text("# Rapport UI\n\n| A | B |\n| --- | --- |\n| x | y |\n", encoding="utf-8")
    try:
        response = client.get("/api/report")
        assert response.status_code == 200
        payload = response.get_json()
        assert "<table>" in payload["html"]
        assert payload["path"].endswith("ui_report.md")

        download = client.get("/api/report/download")
        assert download.status_code == 200
        assert "attachment" in download.headers.get("Content-Disposition", "")
        download.close()
    finally:
        shutil.rmtree(workspace)


def test_report_endpoint_rejects_paths_outside_reports(client):
    forbidden = client.get("/api/report?path=" + APP_PATH.as_posix())
    assert forbidden.status_code == 404


def test_new_project_preview_does_not_create_directory(client, tmp_path):
    parent = tmp_path / "new project parent"
    parent.mkdir()
    preview = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Fresh UI Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Creer une CLI de demonstration.",
        },
    )
    assert preview.status_code == 200
    payload = preview.get_json()
    assert "Invoke-ControlTowerRun.ps1" in payload["command_preview"]
    assert "-BriefPath" in payload["command_preview"]
    assert payload["project"]["target_project_path"].endswith("Fresh_UI_Project")
    assert not (parent / "Fresh_UI_Project").exists()


def test_new_project_preview_rejects_unsafe_project_name(client, tmp_path):
    parent = tmp_path / "new project parent"
    parent.mkdir()
    invalid = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "..\\bad",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "bad",
        },
    )
    assert invalid.status_code == 400


def test_new_project_real_command_persists_brief_to_file(app_module, tmp_path):
    parent = tmp_path / "new project parent"
    parent.mkdir()
    _, real_command, args = app_module.build_new_project_command(
        {
            "project_name": "Fresh UI Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Ligne 1\nLigne 2 preservee",
        },
        run_aider=True,
        persist_brief=True,
    )
    assert "-RunAider" in real_command
    assert "-BriefPath" in real_command
    assert "Ligne 2 preservee" not in real_command
    assert "-RunAider" in args


def test_creation_parent_is_persisted_in_state(client, tmp_path):
    parent = tmp_path / "new project parent"
    parent.mkdir()
    saved = client.post("/api/creation-parent", json={"creation_parent_path": str(parent)})
    assert saved.status_code == 200
    state = client.get("/api/state").get_json()
    assert state["creation_parent_path"] == str(parent)
