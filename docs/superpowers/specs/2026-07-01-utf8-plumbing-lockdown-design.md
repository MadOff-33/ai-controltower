# UTF-8 plumbing lockdown (ControlTower UI + Hermes git hygiene)

**Date:** 2026-07-01
**Status:** Approved
**Origin:** Codex review of the security/reliability pass on `apps/controltower-ui/app.py` (better UI security, no `shell=True`, dynamic project root, pytest suite, reliable validation status). Codex flagged one blocking gap: Windows encoding is not locked down everywhere, which previously broke creation runs (`charmap` errors, `�`, `CrÃ©er` mojibake).

## Goal

Lock the UTF-8 plumbing before judging Aider/Ornith output quality any further. This is explicitly a plumbing fix, not a feature: no new capability is added.

## Non-goals

- No new UI features or workflow steps.
- No change to Aider/Ornith prompting or model behavior.
- No change to the PowerShell layer's actual behavior (see Section 1 — it's already correct; this is a verification finding, not a code change).

## Context gathered

- `apps/controltower-ui/app.py` has six functions that spawn subprocesses. Four already pass `encoding="utf-8", errors="replace"` to `subprocess.run`/`subprocess.Popen`: `run_dynamic_job()`, `cancel_job()`, `run_shell_command()`, `create_ticket_from_report()`. Two do not: `read_json_process()` and the `subprocess.Popen` inside `run_job()`.
- `tools/lib/ControlTowerCommon.ps1` provides `Enable-AiderUtf8Environment` / `Restore-AiderUtf8Environment`, which force `[Console]::OutputEncoding`, `$OutputEncoding`, and `PYTHONIOENCODING=utf-8` around the Aider invocation. `Start-AiderAudit.ps1`, `Start-AiderCreation.ps1`, and `Start-AiderFix.ps1` all call it. `Invoke-ControlTowerRun.ps1`'s own `Write-Host` calls outside that window are fixed, accent-free French strings (`"reserve a une version ulterieure"`, etc.) — there is no accented content flowing through an unprotected code path today.
- Mojibake detection already exists at the PowerShell layer (`Test-AiderOutput.ps1`, `Test-AiderCreation.ps1`, `New-AuditConsolidatedReport.ps1`) and is already covered by PS-level tests (`tools/tests/Test-AiderCreationReliability.ps1`, `tools/tests/Test-AiderReliabilityLayer.ps1`).
- `apps/controltower-ui/tests/test_app.py` has one brief-related scenario using ASCII-only text (`"Creer une CLI de demonstration."`). No test exercises accented input end-to-end.
- `hermes_memory/central/entries.jsonl`, `index.json`, and `guidance_cache.md` changed in each of the last 3 commits (run outputs). `schema.json` has not changed since the feature that introduced it (the versioned socle).
- `tools/Initialize-HermesMemory.ps1` regenerates `entries.jsonl`, `index.json`, `guidance_cache.md`, and `schema.json` from scratch if any are missing, and runs automatically at the start of every `Invoke-ControlTowerRun.ps1` invocation. A fresh clone without these three files stays functional.

## Design

### 1. Force UTF-8 on the two remaining Python subprocess calls

File: `apps/controltower-ui/app.py`

- `read_json_process()`: add `encoding="utf-8", errors="replace"` to its `subprocess.run(...)` call.
- `run_job()`: add `encoding="utf-8", errors="replace"` to its `subprocess.Popen(...)` call.

No other production code changes in `app.py`. No changes to `tools/*.ps1` — the PowerShell UTF-8 encoding wrapper already covers every code path that can carry accented content (Aider stdout during the `Enable-AiderUtf8Environment` window); this is recorded as a verified finding.

### 2. Accented regression tests

File: `apps/controltower-ui/tests/test_app.py`

- Replace the ASCII brief in `test_new_project_preview_does_not_create_directory` and `test_new_project_real_command_persists_brief_to_file` with an accented brief: `"Créer une CLI de démonstration.\né è à ç œ"`. These already assert the brief never appears in the command line and that persisted file content round-trips — extending them with accents closes the exact gap Codex flagged (an ASCII-only test can pass while the real bug stays alive).

New file: `apps/controltower-ui/tests/test_encoding.py`

- `test_read_json_process_decodes_utf8_accents`: calls `read_json_process()` with `[sys.executable, "-c", "..."]` printing `json.dumps({"msg": "Créer é è à ç œ"})`. Asserts the decoded value matches exactly and contains none of `app_module.MOJIBAKE_MARKERS`.
- `test_run_job_captures_utf8_accents_without_mojibake`: monkeypatches `build_commands` to add a fake non-dangerous, non-template command running `[sys.executable, "-c", "print('Créer é è à ç œ')"]`; calls `create_job()`, polls until the job finishes, asserts `job["output"]` matches and contains no mojibake markers. This exercises `run_job()` through its real thread/Popen path, not just a code-shape check.

### 3. End-to-end recipe test (Directive 4)

Same file, `apps/controltower-ui/tests/test_encoding.py`:

- `test_new_project_recipe_utf8_end_to_end`: drives the chain a real run would go through, with Aider mocked (no Ollama/Aider dependency, runs in plain pytest/CI):
  1. Persist an accented brief via `write_creation_brief_request` (or `POST /api/new-project/preview`).
  2. Write a fixture report containing accented text directly under `audits/<workspace>/reports/*.md` (same pattern `test_report_endpoint_renders_markdown_table` already uses), simulating the output of a completed run.
  3. `GET /api/report`: assert `warnings == []` and no mojibake markers in `raw`/`html`.
  4. `GET /api/report/download`: assert the downloaded bytes decode to the same accented text.
- This composes the two unit-level tests above into one scenario proving the pipe holds end-to-end, and gives pytest-level coverage of `report_warnings()`, which previously had none.

### 4. Hermes artifacts out of Git

- `.gitignore`: add
  ```
  hermes_memory/central/entries.jsonl
  hermes_memory/central/index.json
  hermes_memory/central/guidance_cache.md
  ```
  `hermes_memory/central/schema.json` stays tracked (the socle).
- `git rm --cached` the three files above (kept on disk, dropped from tracking) in the same commit as the `.gitignore` change.
- No PowerShell changes needed: `Initialize-HermesMemory.ps1` already recreates all four files on demand.

## Testing / verification plan

- `python -m pytest apps/controltower-ui/tests` — all existing tests plus the new/extended ones must pass.
- Manual sanity check: confirm `git status` no longer shows `hermes_memory/central/{entries.jsonl,index.json,guidance_cache.md}` as tracked after the `git rm --cached`, and that a subsequent local run still regenerates them without error.
- No changes to the PowerShell test suite (`tools/tests/*`) are required; existing PS-level mojibake tests remain the source of truth for that layer.

## Risks / open questions

- None identified — this is a narrowly-scoped plumbing fix confirmed against the current code, not a speculative one.
