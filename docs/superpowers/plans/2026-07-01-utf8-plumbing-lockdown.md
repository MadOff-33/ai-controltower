# UTF-8 Plumbing Lockdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the two remaining unencoded Python subprocess calls in the ControlTower Flask UI, add accented-content regression tests that actually reproduce the historical `charmap`/mojibake bug, and stop Hermes run-output files from polluting every commit.

**Architecture:** Two one-line `subprocess` kwarg additions in `apps/controltower-ui/app.py`, three new/extended pytest tests that spawn a real child process writing raw UTF-8 bytes (so the tests fail before the fix and pass after, on any Windows locale), and a `.gitignore` + `git rm --cached` change for three Hermes memory files.

**Tech Stack:** Python 3.12 (Flask), pytest, PowerShell 5.1/7. No new dependencies.

## Global Constraints

- No new features or workflow steps — this is a plumbing fix only (per spec: [2026-07-01-utf8-plumbing-lockdown-design.md](../specs/2026-07-01-utf8-plumbing-lockdown-design.md)).
- Scope is `apps/controltower-ui/app.py` and its tests, plus `.gitignore` / Hermes tracking. No changes to `tools/*.ps1` — the design confirmed the PowerShell UTF-8 wrapper (`Enable-AiderUtf8Environment`) already covers every code path that can carry accented content.
- All new/changed subprocess calls in `app.py` must pass `encoding="utf-8", errors="replace"`.
- `hermes_memory/central/schema.json` stays tracked in git; `entries.jsonl`, `index.json`, `guidance_cache.md` do not.
- Test command from repo root: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` (uses the project's existing `.venv` at `apps/controltower-ui/.venv`).

---

### Task 1: Fix `read_json_process()` to decode UTF-8 explicitly

**Files:**
- Modify: `apps/controltower-ui/app.py:140-151` (function `read_json_process`)
- Test: `apps/controltower-ui/tests/test_encoding.py` (new file)

**Interfaces:**
- Consumes: `app_module` fixture from `apps/controltower-ui/tests/conftest.py` (session-scoped, loads `app.py` via `importlib`).
- Produces: `app_module.read_json_process(command: list[str]) -> dict` now decodes stdout as UTF-8 regardless of host locale. `app_module.MOJIBAKE_MARKERS` (existing list `["Ã", "Â", "â", "�"]`) is reused by later tasks.

- [ ] **Step 1: Create the test file and write the failing test**

Create `apps/controltower-ui/tests/test_encoding.py`:

```python
import sys

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
```

Note: the child process writes raw UTF-8 bytes via `sys.stdout.buffer.write(...)` instead of a plain `print(...)`. This bypasses the child's own default text-mode stdout encoding, so the test isolates and proves exactly one thing: whether `read_json_process`'s parent-side `subprocess.run` decodes those bytes as UTF-8. Without the fix, `subprocess.run(text=True)` decodes using `locale.getpreferredencoding()`, which on a non-UTF-8 Windows locale (e.g. French cp1252) turns the bytes for "é" into "Ã©" — the exact `CrÃ©er` bug from the report.

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: `test_read_json_process_decodes_utf8_accents` FAILS — either a `UnicodeDecodeError`/`json.JSONDecodeError`, or an assertion failure showing `result["msg"]` contains `Ã©`/`�` instead of the correct accented text (exact symptom depends on host locale; on a UTF-8-default host the test may pass without the fix — if so, note this in the task and proceed to Step 3 anyway since the fix is still correct and required for non-UTF-8 hosts).

- [ ] **Step 3: Implement the fix**

In `apps/controltower-ui/app.py`, change `read_json_process`:

```python
def read_json_process(command):
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        shell=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip())
    return json.loads(completed.stdout)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: `test_read_json_process_decodes_utf8_accents` PASSES.

- [ ] **Step 5: Commit**

```bash
git add apps/controltower-ui/app.py apps/controltower-ui/tests/test_encoding.py
git commit -m "fix: force utf-8 decoding in read_json_process"
```

---

### Task 2: Fix `run_job()`'s `subprocess.Popen` to decode UTF-8 explicitly

**Files:**
- Modify: `apps/controltower-ui/app.py:662-740` (function `run_job`, specifically the `subprocess.Popen` call around line 684)
- Test: `apps/controltower-ui/tests/test_encoding.py`

**Interfaces:**
- Consumes: `app_module.create_job(command_key: str, project_path: str, confirmed: bool = False) -> dict` (existing), `app_module.JOBS: dict[str, dict]` (existing module-level job table), `app_module.JOBS_LOCK: threading.Lock` (existing), `app_module.build_commands(project_path: str) -> dict` and `app_module.ALLOWED_COMMANDS: set[str]` (existing, monkeypatched by the test).
- Produces: `run_job` now decodes the spawned process's stdout as UTF-8, so `job["output"]` never contains mojibake for correctly UTF-8-encoded child output.

- [ ] **Step 1: Write the failing test**

Append to `apps/controltower-ui/tests/test_encoding.py`:

```python
import time


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
```

`ACCENTED_TEXT` and `sys` are already defined at module scope by Task 1's edit; `time` needs to be imported at the top of the file alongside `sys`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: `test_run_job_captures_utf8_accents_without_mojibake` FAILS (job output contains mojibake, or the assertion on `finished["output"] == ACCENTED_TEXT` fails) on a non-UTF-8-default host. As in Task 1, if the host locale happens to already be UTF-8, the test may pass before the fix — proceed to Step 3 regardless, since the fix is still required for correctness on other hosts.

- [ ] **Step 3: Implement the fix**

In `apps/controltower-ui/app.py`, inside `run_job`, change the `subprocess.Popen` call:

```python
            process = subprocess.Popen(
                item["args"],
                cwd=str(ROOT),
                text=True,
                encoding="utf-8",
                errors="replace",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                shell=False,
                bufsize=1,
            )
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: both `test_encoding.py` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/controltower-ui/app.py apps/controltower-ui/tests/test_encoding.py
git commit -m "fix: force utf-8 decoding in run_job subprocess output"
```

---

### Task 3: Extend existing brief tests with accented content

**Files:**
- Modify: `apps/controltower-ui/tests/test_app.py:42-59` (`test_new_project_preview_does_not_create_directory`)
- Modify: `apps/controltower-ui/tests/test_app.py:77-93` (`test_new_project_real_command_persists_brief_to_file`)

**Interfaces:**
- Consumes: `app_module.build_new_project_command(payload: dict, run_aider: bool, persist_brief: bool) -> tuple[dict, str, list[str]]` (existing, unchanged), `app_module.MOJIBAKE_MARKERS` (from Task 1).
- Produces: no new production interfaces — these are regression tests over existing, already-correct behavior (brief text is never interpolated into the command line; it is always written to a file).

- [ ] **Step 1: Update `test_new_project_preview_does_not_create_directory`**

In `apps/controltower-ui/tests/test_app.py`, replace the whole function:

```python
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
```

- [ ] **Step 2: Update `test_new_project_real_command_persists_brief_to_file`**

In the same file, replace the whole function:

```python
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
```

`Path` is already imported at the top of `test_app.py` (`from pathlib import Path`).

- [ ] **Step 3: Run the tests to verify they pass**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: `test_new_project_preview_does_not_create_directory` and `test_new_project_real_command_persists_brief_to_file` both PASS (these test existing, already-correct behavior — no production code change is needed for this task).

- [ ] **Step 4: Commit**

```bash
git add apps/controltower-ui/tests/test_app.py
git commit -m "test: cover new-project brief handling with accented input"
```

---

### Task 4: End-to-end accented recipe test (create → report → download)

**Files:**
- Modify: `apps/controltower-ui/tests/test_encoding.py`

**Interfaces:**
- Consumes: `client` fixture from `conftest.py` (Flask test client), `GET /api/report` and `GET /api/report/download` routes (existing, unchanged), `app_module.MOJIBAKE_MARKERS`.
- Produces: no new production interfaces — proves the existing `/api/report` → `report_warnings()` → `/api/report/download` chain is mojibake-free for accented report content, and gives it pytest coverage for the first time.

- [ ] **Step 1: Write the test**

Append to `apps/controltower-ui/tests/test_encoding.py`:

```python
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


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
        assert download.data.decode("utf-8") == report_text
        download.close()
    finally:
        shutil.rmtree(workspace)
```

Move the `import sys` already at the top of the file if needed so `sys`, `time`, `shutil`, and `Path` are all imported once at the top of `test_encoding.py` (no duplicate imports across the file).

- [ ] **Step 2: Run the test to verify it passes**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: `test_new_project_recipe_utf8_end_to_end` PASSES, and all of `apps/controltower-ui/tests` (both `test_app.py` and `test_encoding.py`) pass together.

- [ ] **Step 3: Commit**

```bash
git add apps/controltower-ui/tests/test_encoding.py
git commit -m "test: add end-to-end utf-8 recipe test for report create/read/download"
```

---

### Task 5: Stop Hermes run-output files from being tracked in git

**Files:**
- Modify: `.gitignore`
- Untrack (keep on disk): `hermes_memory/central/entries.jsonl`, `hermes_memory/central/index.json`, `hermes_memory/central/guidance_cache.md`

**Interfaces:**
- None (no code interfaces — this is a git-tracking-only change). `hermes_memory/central/schema.json` remains tracked and unaffected. `tools/Initialize-HermesMemory.ps1` (unchanged) already regenerates all four files if any are missing.

- [ ] **Step 1: Add the three run-output files to `.gitignore`**

In `.gitignore`, after the existing `hermes_lab/` line, add:

```
hermes_memory/central/entries.jsonl
hermes_memory/central/index.json
hermes_memory/central/guidance_cache.md
```

The full relevant section of `.gitignore` should read:

```
audits/
creation_workspaces/
logs/controltower_runs/
logs/ui_jobs/
hermes_lab/
hermes_memory/central/entries.jsonl
hermes_memory/central/index.json
hermes_memory/central/guidance_cache.md
ControlTower.exe
logs/final_recipe_report.md
```

- [ ] **Step 2: Untrack the three files (keep them on disk)**

```bash
git rm --cached hermes_memory/central/entries.jsonl hermes_memory/central/index.json hermes_memory/central/guidance_cache.md
```

- [ ] **Step 3: Verify the files still exist locally and are now ignored**

Run: `git status --porcelain -- hermes_memory`

Expected: no output for `entries.jsonl`, `index.json`, or `guidance_cache.md` (they're ignored, not just untracked — if they show as `??` instead of not appearing at all, re-check Step 1's `.gitignore` paths match exactly). `schema.json` must not appear in this output either, since it was never modified and remains tracked as-is.

Run (PowerShell, from repo root): `Test-Path hermes_memory\central\entries.jsonl`

Expected: `True` — the file is still present on disk after `git rm --cached`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: stop tracking hermes run-output files, keep schema.json versioned"
```

---

## Final verification

- [ ] Run the full suite once more from repo root: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` — all tests pass, including the three new `test_encoding.py` tests and the two extended `test_app.py` tests.
- [ ] Run `git status` — working tree is clean, `hermes_memory/central/{entries.jsonl,index.json,guidance_cache.md}` are absent from the listing, `schema.json` is untouched.
