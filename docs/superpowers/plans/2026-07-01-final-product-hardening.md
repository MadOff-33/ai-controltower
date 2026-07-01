# Final Product Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the six closure features: executable launcher, asynchronous jobs, guided workflow, ticket from report, run summaries, and final recipe.

**Architecture:** PowerShell remains the reliable execution layer. Flask exposes a local cockpit with a command allowlist, background jobs, workflow state, and artifact links. Windows packaging is produced from a small C# launcher source rather than committing a binary.

**Tech Stack:** PowerShell 5.1, Flask, vanilla JS/CSS, .NET Framework C# compiler for `ControlTower.exe`.

---

### Task 1: Launcher

**Files:**
- Create: `ControlTower.cmd`
- Create: `launchers/ControlTowerLauncher.cs`
- Create: `tools/Build-ControlTowerLauncher.ps1`

- [x] Add root command launcher.
- [x] Add C# source for `ControlTower.exe`.
- [x] Add PowerShell builder using .NET Framework `csc.exe`.
- [x] Verify builder produces `C:\AI_ControlTower\ControlTower.exe`.

### Task 2: Jobs and Workflow

**Files:**
- Modify: `apps/controltower-ui/app.py`
- Modify: `apps/controltower-ui/templates/index.html`
- Modify: `apps/controltower-ui/static/app.js`
- Modify: `apps/controltower-ui/static/styles.css`

- [x] Add `WORKFLOW_STEPS`.
- [x] Add `/api/jobs` and `/api/jobs/<job_id>`.
- [x] Run catalog commands through jobs.
- [x] Add job panel and polling.
- [x] Add last-run status and artifact display.

### Task 3: Ticket From Report

**Files:**
- Create: `tools/New-AiderFixTicketFromReport.ps1`
- Modify: `apps/controltower-ui/app.py`

- [x] Add report-to-ticket generator.
- [x] Keep generated tickets inside workspace `fix_tickets/`.
- [x] Add `/api/tickets/from-report`.

### Task 4: Run Summary

**Files:**
- Modify: `tools/Invoke-ControlTowerRun.ps1`

- [x] Generate `*.summary.md` beside each run log.
- [x] Include mode, status, artifacts, and next action.

### Task 5: Final Recipe

**Files:**
- Create: `tools/Test-ControlTowerFinalRecipe.ps1`

- [x] Verify dependencies.
- [x] Verify UI self-test.
- [x] Optionally run full suite.
- [x] Run a fast dry-run on a fixture by default.
- [x] Produce `logs/final_recipe_report.md`.

### Task 6: Tests and Docs

**Files:**
- Modify: `tools/tests/Test-ControlTowerUI.ps1`
- Modify: `README.md`
- Modify: `docs/ux_ui_audit_and_final_roadmap.md`

- [x] Add contract checks for new files and APIs.
- [x] Document launcher and final recipe commands.
- [x] Mark roadmap phases as V1 implemented.
