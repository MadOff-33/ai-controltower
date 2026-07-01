import sys
import time

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
