import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

ACCENTED_TEXT = "Créer é è à ç œ"


def test_read_json_process_decodes_utf8_accents(app_module):
    child_script = (
        "import sys, json\n"
        "data = json.dumps({'msg': 'Créer é è à ç œ'})\n"
        "sys.stdout.buffer.write(data.encode('utf-8'))\n"
    )
    command = [sys.executable, "-c", child_script]

    result = app_module.read_json_process(command)

    assert result["msg"] == ACCENTED_TEXT
    assert not any(marker in result["msg"] for marker in app_module.MOJIBAKE_MARKERS)


def test_run_job_captures_utf8_accents_without_mojibake(app_module, monkeypatch, tmp_path):
    child_script = (
        "import sys\n"
        "sys.stdout.buffer.write('Créer é è à ç œ'.encode('utf-8'))\n"
    )
    fake_command = {
        "label": "Fake accents",
        "group": "Test",
        "dangerous": False,
        "template": False,
        "description": "test fixture command",
        "command": f"{sys.executable} -c ...",
        "args": [sys.executable, "-c", child_script],
    }

    def fake_build_commands(project_path):
        return {"fake_accents": fake_command}

    monkeypatch.setattr(app_module, "build_commands", fake_build_commands)
    monkeypatch.setattr(app_module, "ALLOWED_COMMANDS", {"fake_accents"})

    job = app_module.create_job("fake_accents", str(tmp_path))

    finished = None
    for _ in range(100):
        with app_module.JOBS_LOCK:
            current = dict(app_module.JOBS[job["id"]])
        if current["status"] in ("succeeded", "failed", "canceled"):
            finished = current
            break
        time.sleep(0.05)

    assert finished is not None, "job did not finish within timeout"
    assert finished["status"] == "succeeded"
    assert finished["output"] == ACCENTED_TEXT
    assert not any(marker in finished["output"] for marker in app_module.MOJIBAKE_MARKERS)


def test_new_project_recipe_utf8_end_to_end(client, app_module):
    workspace = ROOT / "audits" / "20990101-000000_utf8_recipe_fixture"
    report_dir = workspace / "reports"
    report_text = "# Rapport UI\n\nCréer une CLI de démonstration.\né è à ç œ\n"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / "utf8_recipe_report.md"
    report_path.write_text(report_text, encoding="utf-8")
    try:
        response = client.get("/api/report")
        assert response.status_code == 200
        payload = response.get_json()
        assert payload["warnings"] == []
        assert "Créer" in payload["raw"]
        assert not any(marker in payload["raw"] for marker in app_module.MOJIBAKE_MARKERS)
        assert not any(marker in payload["html"] for marker in app_module.MOJIBAKE_MARKERS)

        download = client.get("/api/report/download")
        assert download.status_code == 200
        download_text = download.data.decode("utf-8")
        # Normalize line endings for comparison (Flask on Windows may use \r\n)
        assert download_text.replace("\r\n", "\n") == report_text
        assert "Créer" in download_text
        assert not any(marker in download_text for marker in app_module.MOJIBAKE_MARKERS)
        download.close()
    finally:
        shutil.rmtree(workspace)
