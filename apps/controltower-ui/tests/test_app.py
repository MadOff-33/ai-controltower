import json
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
    brief_text = "Créer une CLI de démonstration.\né è à ç œ"
    preview = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Fresh UI Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": brief_text,
        },
    )
    assert preview.status_code == 200
    payload = preview.get_json()
    assert "Invoke-ControlTowerRun.ps1" in payload["command_preview"]
    assert "-BriefPath" in payload["command_preview"]
    assert brief_text not in payload["command_preview"]
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
    brief_text = "Créer une CLI de démonstration.\né è à ç œ"
    _, real_command, args = app_module.build_new_project_command(
        {
            "project_name": "Fresh UI Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": brief_text,
        },
        run_aider=True,
        persist_brief=True,
    )
    assert "-RunAider" in real_command
    assert "-BriefPath" in real_command
    assert brief_text not in real_command
    assert "-RunAider" in args

    brief_path = Path(args[args.index("-BriefPath") + 1])
    persisted = brief_path.read_text(encoding="utf-8")
    assert persisted == brief_text
    assert not any(marker in persisted for marker in app_module.MOJIBAKE_MARKERS)


def test_creation_parent_is_persisted_in_state(client, tmp_path):
    parent = tmp_path / "new project parent"
    parent.mkdir()
    saved = client.post("/api/creation-parent", json={"creation_parent_path": str(parent)})
    assert saved.status_code == 200
    state = client.get("/api/state").get_json()
    assert state["creation_parent_path"] == str(parent)


def test_state_endpoint_exposes_model_health_check_command(client):
    state = client.get("/api/state")
    assert state.status_code == 200
    payload = state.get_json()
    assert "model_health_check" in payload["commands"]
    command = payload["commands"]["model_health_check"]
    assert command["dangerous"] is False
    assert "Test-ModelServingHealth.ps1" in command["command"]


def test_new_project_status_reports_no_previous_project(client, tmp_path):
    parent = tmp_path / "status parent"
    parent.mkdir()
    response = client.get(
        "/api/new-project/status",
        query_string={"project_name": "Never Created", "parent_path": str(parent)},
    )
    assert response.status_code == 200
    payload = response.get_json()
    assert payload["has_previous"] is False
    assert payload["functional_status"] is None


def test_new_project_preview_allows_existing_when_flagged(client, tmp_path):
    parent = tmp_path / "existing parent"
    parent.mkdir()
    target = parent / "Existing_Project"
    target.mkdir()
    (target / "placeholder.txt").write_text("deja present", encoding="utf-8")
    rejected = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Existing Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Nouveau brief.",
        },
    )
    assert rejected.status_code == 400

    accepted = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Existing Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Nouveau brief.",
            "allow_existing": True,
        },
    )
    assert accepted.status_code == 200
    assert "-AllowExisting" in accepted.get_json()["command_preview"]


def test_new_project_status_matches_resolved_non_canonical_parent_path(client, tmp_path):
    # The parent path is passed in a non-canonical form (a "../<same dir>" traversal
    # segment) to prove the match survives real resolution, not just a trivial
    # already-resolved case. A trailing "\.\ " segment is collapsed by pathlib's `/`
    # join *before* .resolve() is ever called, so unresolved and resolved forms are
    # byte-identical for that input and it doesn't actually exercise resolution. A
    # ".." traversal genuinely differs as a string between Path(x) and Path(x).resolve()
    # while still pointing at the same real directory, so it does exercise the bug.
    parent = tmp_path / "status resolve parent"
    parent.mkdir()
    resolved_target = parent.resolve() / "Resolved_Project"
    non_canonical_parent = str(parent) + "\\..\\" + parent.name

    workspace = ROOT / "creation_workspaces" / "20990101-000000_resolved_project_fixture"
    validation_dir = workspace / "validation"
    validation_dir.mkdir(parents=True, exist_ok=True)
    try:
        (workspace / "creation.config.json").write_text(
            json.dumps({"target_project_path": str(resolved_target)}),
            encoding="utf-8",
        )
        (validation_dir / "creation_result.json").write_text(
            json.dumps(
                {
                    "functional_check": {
                        "status": "failed",
                        "checks": [{"name": "browser_console", "status": "failed"}],
                    }
                }
            ),
            encoding="utf-8",
        )

        response = client.get(
            "/api/new-project/status",
            query_string={"project_name": "Resolved Project", "parent_path": non_canonical_parent},
        )
        assert response.status_code == 200
        payload = response.get_json()
        assert payload["has_previous"] is True
        assert payload["functional_status"] == "failed"
    finally:
        shutil.rmtree(workspace)
