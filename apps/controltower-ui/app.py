import argparse
import html
import json
import os
import re
import subprocess
import sys
import threading
import time
import webbrowser
import uuid
from pathlib import Path


ROOT = Path("C:/AI_ControlTower")
APP_DIR = ROOT / "apps" / "controltower-ui"
STATE_PATH = APP_DIR / "state.json"
LOG_LIMIT = 300
JOB_OUTPUT_LIMIT = 60000
JOB_STALL_SECONDS = 300
LOGS = []
LOG_LOCK = threading.Lock()
JOBS = {}
JOB_PROCESSES = {}
JOBS_LOCK = threading.Lock()
JOB_LOG_DIR = ROOT / "logs" / "ui_jobs"
MOJIBAKE_MARKERS = ["Ã", "Â", "â–º", "âœ", "â", "�"]
PROJECT_TYPES = ["python-cli", "python-app", "webapp", "api", "desktop", "library", "other"]

WORKFLOW_STEPS = [
    {"id": "project", "label": "Selectionner projet", "command": None},
    {"id": "deps", "label": "Verifier dependances", "command": None},
    {"id": "audit_dry_run", "label": "Audit dry-run", "command": "audit_dry_run"},
    {"id": "audit_real", "label": "Audit reel", "command": "audit_real"},
    {"id": "continue_audit", "label": "Continuer audit", "command": "continue_audit"},
    {"id": "ticket_from_report", "label": "Creer ticket depuis rapport", "command": "ticket_from_report"},
    {"id": "fix_dry_run", "label": "Fix dry-run", "command": "fix_dry_run"},
    {"id": "fix_real", "label": "Fix reel", "command": "fix_real"},
    {"id": "final_recipe", "label": "Recette finale", "command": "final_recipe"},
]


def quote_arg(value):
    return '"' + str(value).replace('"', '\\"') + '"'


def sanitize_project_name(name):
    value = str(name or "").strip()
    if not value or value in (".", ".."):
        raise ValueError("Nom de projet invalide.")
    if re.search(r'[\\/:*?"<>|]', value):
        raise ValueError("Nom de projet invalide: caractere Windows interdit.")
    safe = re.sub(r"[^a-zA-Z0-9_.-]", "_", value).strip("_")
    if not safe or safe in (".", ".."):
        raise ValueError("Nom de projet invalide.")
    return safe


def validate_new_project_payload(payload):
    name = sanitize_project_name(payload.get("project_name") or payload.get("name"))
    parent = Path(str(payload.get("parent_path") or payload.get("parent_dir") or "")).expanduser()
    brief = str(payload.get("brief") or "").strip()
    project_type = str(payload.get("project_type") or "python-basic").strip() or "python-basic"
    if project_type not in PROJECT_TYPES and project_type != "python-basic":
        project_type = "other"
    if not brief:
        raise ValueError("Brief projet obligatoire.")
    if not parent.exists() or not parent.is_dir():
        raise ValueError("Le dossier parent n'existe pas.")
    target = parent / name
    if target.exists() and any(target.iterdir()):
        raise ValueError("Le dossier projet existe deja et n'est pas vide.")
    return {
        "project_name": name,
        "parent_path": str(parent.resolve()),
        "project_type": project_type,
        "brief": brief,
        "target_project_path": str(target),
    }


def build_new_project_command(payload, run_aider=False):
    data = validate_new_project_payload(payload)
    command = (
        'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" '
        '-Mode Creation -ProjectName '
        + quote_arg(data["project_name"])
        + " -ParentPath "
        + quote_arg(data["parent_path"])
        + " -ProjectType "
        + quote_arg(data["project_type"])
        + " -Brief "
        + quote_arg(data["brief"])
        + " -WorkspaceRoot "
        + quote_arg("C:\\AI_ControlTower\\creation_workspaces")
    )
    if run_aider:
        command += " -RunAider"
    else:
        command += " -ValidateAfterDryRun"
    return data, command


def read_json_process(command):
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        shell=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip())
    return json.loads(completed.stdout)


def load_state(default_project=None):
    state = {
        "audit_project_path": str(default_project or ROOT),
        "creation_parent_path": "D:\\Dev",
    }
    if STATE_PATH.exists():
        try:
            loaded = json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if loaded.get("audit_project_path"):
                state["audit_project_path"] = loaded["audit_project_path"]
            elif loaded.get("last_project_path"):
                state["audit_project_path"] = loaded["last_project_path"]
            if loaded.get("creation_parent_path"):
                state["creation_parent_path"] = loaded["creation_parent_path"]
        except Exception:
            pass
    return state


def save_state_value(key, value, default_project=None):
    state = load_state(default_project)
    state[key] = str(value)
    state["last_project_path"] = state.get("audit_project_path", str(default_project or ROOT))
    STATE_PATH.write_text(json.dumps(state, indent=2), encoding="utf-8")


def save_state(project_path):
    save_state_value("audit_project_path", project_path)


def save_creation_parent(parent_path):
    save_state_value("creation_parent_path", parent_path)


def get_git_info(project_path):
    return read_json_process(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "tools" / "Get-ProjectGitInfo.ps1"),
            "-ProjectPath",
            str(project_path),
        ]
    )


def get_dependency_info(project_path):
    return read_json_process(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "tools" / "Test-ControlTowerDependencies.ps1"),
            "-ProjectPath",
            str(project_path),
            "-HermesMemoryRoot",
            str(ROOT / "hermes_memory"),
        ]
    )


def build_commands(project_path):
    project = quote_arg(project_path)
    latest_workspace = newest_workspace() if "newest_workspace" in globals() else ""
    latest_workspace_arg = quote_arg(latest_workspace) if latest_workspace else '"<LATEST_WORKSPACE>"'
    workspace = '"<WORKSPACE_PATH>"'
    ticket = '"<TICKET_PATH>"'
    return {
        "install": {
            "label": "Installer / reparer ControlTower",
            "group": "Systeme",
            "dangerous": False,
            "template": False,
            "description": "Verifie et remet en place les dossiers, scripts, memoire Hermes et prerequis ControlTower.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Install-ControlTower.ps1"',
        },
        "audit_dry_run": {
            "label": "Audit dry-run",
            "group": "Audit",
            "dangerous": False,
            "template": False,
            "description": "Prepare un workspace d'audit, cree le snapshot, inventorie le projet et valide la structure sans lancer Aider.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath '
            + project
            + " -ValidateAfterDryRun",
        },
        "audit_real": {
            "label": "Audit reel avec Aider",
            "group": "Audit",
            "dangerous": True,
            "template": False,
            "description": "Lance Aider avec Ornith sur un pack de contexte cadre et produit un rapport valide dans reports.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath '
            + project
            + " -RunAider",
        },
        "continue_audit": {
            "label": "Continuer audit",
            "group": "Audit",
            "dangerous": True,
            "template": False,
            "description": "Reprend le dernier audit avec les fichiers omis du pack precedent pour tendre vers une couverture complete.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-AiderAuditContinuation.ps1" -WorkspacePath '
            + latest_workspace_arg
            + " -RunAider",
        },
        "new_project": {
            "label": "Nouveau projet",
            "group": "Creation",
            "dangerous": False,
            "template": True,
            "description": "Socle vibe coding: preparer un dossier neuf, cadrer l'intention, puis faire generer par Aider dans un workspace isole. Le pipeline complet arrive dans le sprint creation.",
            "command": "Mode creation a venir: choisir un dossier vide, decrire le produit, generer un plan, puis lancer Aider sur un workspace de creation isole.",
        },
        "fix_dry_run": {
            "label": "Fix dry-run depuis ticket",
            "group": "Correction",
            "dangerous": False,
            "template": True,
            "description": "Affiche la commande de correction a partir d'un ticket sans lancer Aider ni modifier le snapshot.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Fix -WorkspacePath '
            + workspace
            + " -TicketPath "
            + ticket
            + " -ValidateAfterDryRun",
        },
        "fix_real": {
            "label": "Fix reel avec Aider",
            "group": "Correction",
            "dangerous": True,
            "template": True,
            "description": "Lance une correction cadree par ticket dans le snapshot d'audit, puis valide les fichiers autorises.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Fix -WorkspacePath '
            + workspace
            + " -TicketPath "
            + ticket
            + " -RunAider",
        },
        "tests": {
            "label": "Tests complets",
            "group": "Qualite",
            "dangerous": False,
            "template": False,
            "description": "Execute la suite de tests ControlTower pour verifier scripts, UI, encodage et validateurs.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\tests\\Invoke-ControlTowerTestSuite.ps1"',
        },
        "final_recipe": {
            "label": "Recette finale projet",
            "group": "Qualite",
            "dangerous": False,
            "template": False,
            "description": "Deroule la recette finale sur le projet cible pour confirmer que le cockpit et le pipeline restent utilisables.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Test-ControlTowerFinalRecipe.ps1" -ProjectPath '
            + project
            + " -SkipFullSuite",
        },
        "hermes_guidance": {
            "label": "Guidance Hermes",
            "group": "Memoire",
            "dangerous": False,
            "template": False,
            "description": "Genere ou affiche la guidance issue de la memoire centrale Hermes pour reutiliser l'experience des runs.",
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Get-HermesGuidance.ps1"',
        },
        "git_status": {
            "label": "Git status",
            "group": "Git",
            "dangerous": False,
            "template": False,
            "description": "Affiche l'etat Git du projet cible afin de voir les fichiers modifies, ajoutes ou non suivis.",
            "command": "git -C " + project + " status",
        },
        "git_diff": {
            "label": "Git diff",
            "group": "Git",
            "dangerous": False,
            "template": False,
            "description": "Affiche les changements locaux du projet cible avant une correction ou une revue.",
            "command": "git -C " + project + " diff",
        },
        "aider_manual": {
            "label": "Aider manuel cadre",
            "group": "Aider",
            "dangerous": True,
            "template": False,
            "description": "Ouvre une commande Aider cadree sur Ornith pour usage manuel avance, hors pipeline automatise.",
            "command": "aider --model ollama_chat/ornith:9b --no-auto-commits --no-dirty-commits",
        },
    }


ALLOWED_COMMANDS = set(build_commands(ROOT).keys())


def add_log(level, message, output=""):
    entry = {
        "time": time.strftime("%H:%M:%S"),
        "level": level,
        "message": message,
        "output": output,
    }
    with LOG_LOCK:
        LOGS.append(entry)
        del LOGS[:-LOG_LIMIT]
    return entry


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def append_job_output(job_id, text):
    if not text:
        return
    JOB_LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = JOB_LOG_DIR / (job_id + ".log")
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(text)
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if not job:
            return
        job["output"] = (job.get("output", "") + text)[-JOB_OUTPUT_LIMIT:]
        job["last_activity_at"] = now_iso()
        job["last_activity_ts"] = time.time()
        job["log_path"] = str(log_path)
        job["stalled"] = False
        job["health"] = "active"


def refresh_job_health(job):
    status = job.get("status")
    if status in ("queued", "running"):
        last_activity_ts = job.get("last_activity_ts") or 0
        silence_seconds = int(max(0, time.time() - last_activity_ts)) if last_activity_ts else 0
        job["silence_seconds"] = silence_seconds
        if status == "running" and silence_seconds >= JOB_STALL_SECONDS:
            job["stalled"] = True
            job["health"] = "stalled"
            job["status_label"] = "Aucune activite recente"
        else:
            job["stalled"] = False
            job["health"] = "active" if status == "running" else "queued"
            job["status_label"] = "En cours" if status == "running" else "En attente"
    return job


def public_job(job):
    public = dict(job)
    public.pop("last_activity_ts", None)
    return refresh_job_health(public)


def newest_workspace():
    audits = ROOT / "audits"
    if not audits.exists():
        return ""
    workspaces = [p for p in audits.iterdir() if p.is_dir()]
    if not workspaces:
        return ""
    return str(max(workspaces, key=lambda p: p.stat().st_mtime))


def latest_artifacts():
    workspace = newest_workspace()
    if not workspace:
        return {"workspace": "", "report": "", "validation": "", "run_log": "", "summary": ""}
    workspace_path = Path(workspace)
    reports = sorted((workspace_path / "reports").glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True) if (workspace_path / "reports").exists() else []
    validations = sorted((workspace_path / "validation").glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True) if (workspace_path / "validation").exists() else []
    logs_dir = ROOT / "logs" / "controltower_runs"
    logs = sorted(logs_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True) if logs_dir.exists() else []
    summaries = sorted(logs_dir.glob("*.summary.md"), key=lambda p: p.stat().st_mtime, reverse=True) if logs_dir.exists() else []
    return {
        "workspace": workspace,
        "report": str(reports[0]) if reports else "",
        "validation": str(validations[0]) if validations else "",
        "run_log": str(logs[0]) if logs else "",
        "summary": str(summaries[0]) if summaries else "",
    }


def is_path_inside(child, parent):
    try:
        Path(child).resolve().relative_to(Path(parent).resolve())
        return True
    except Exception:
        return False


def find_report_path(requested_path=""):
    artifacts = latest_artifacts()
    workspace = artifacts.get("workspace")
    if requested_path:
        candidate = Path(requested_path)
        if candidate.exists() and candidate.suffix.lower() == ".md" and workspace and is_path_inside(candidate, workspace):
            return candidate
        return None
    report = artifacts.get("report")
    return Path(report) if report else None


def report_warnings(text):
    markers = [marker for marker in MOJIBAKE_MARKERS if marker in text]
    warnings = []
    if markers:
        warnings.append("Caracteres suspects detectes: " + ", ".join(sorted(set(markers))))
    return warnings


def render_inline(text):
    escaped = html.escape(text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)


def flush_table(lines):
    rows = []
    for line in lines:
        cells = [render_inline(cell.strip()) for cell in line.strip().strip("|").split("|")]
        rows.append(cells)
    if not rows:
        return ""
    header = rows[0]
    body = rows[2:] if len(rows) > 1 and all(set(cell) <= set("-: ") for cell in rows[1]) else rows[1:]
    head_html = "".join("<th>{0}</th>".format(cell) for cell in header)
    body_html = "".join("<tr>{0}</tr>".format("".join("<td>{0}</td>".format(cell) for cell in row)) for row in body)
    return "<table><thead><tr>{0}</tr></thead><tbody>{1}</tbody></table>".format(head_html, body_html)


def render_markdown_report(text):
    parts = []
    table_lines = []
    in_code = False
    code_lines = []
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if line.startswith("```"):
            if in_code:
                parts.append("<pre><code>{0}</code></pre>".format(html.escape("\n".join(code_lines))))
                code_lines = []
                in_code = False
            else:
                if table_lines:
                    parts.append(flush_table(table_lines))
                    table_lines = []
                in_code = True
            continue
        if in_code:
            code_lines.append(line)
            continue
        if line.startswith("|") and line.endswith("|"):
            table_lines.append(line)
            continue
        if table_lines:
            parts.append(flush_table(table_lines))
            table_lines = []
        if not line.strip():
            continue
        heading = re.match(r"^(#{1,4})\s+(.*)$", line)
        if heading:
            level = len(heading.group(1))
            parts.append("<h{0}>{1}</h{0}>".format(level, render_inline(heading.group(2))))
        elif line.lstrip().startswith(("- ", "* ")):
            parts.append("<p class=\"list-line\">{0}</p>".format(render_inline(line.lstrip()[2:])))
        else:
            parts.append("<p>{0}</p>".format(render_inline(line)))
    if table_lines:
        parts.append(flush_table(table_lines))
    if code_lines:
        parts.append("<pre><code>{0}</code></pre>".format(html.escape("\n".join(code_lines))))
    return "\n".join(parts)


def read_audit_coverage():
    workspace = newest_workspace()
    if not workspace:
        return {"status": "none", "label": "Aucun audit lance"}
    workspace_path = Path(workspace)
    manifests_dir = workspace_path / "context_packs"
    manifests = sorted(manifests_dir.glob("*_manifest.json"), key=lambda p: p.stat().st_mtime, reverse=True) if manifests_dir.exists() else []
    if not manifests:
        return {"status": "none", "label": "Aucun pack de contexte recent", "workspace": workspace}
    try:
        manifest = json.loads(manifests[0].read_text(encoding="utf-8"))
    except Exception as exc:
        return {"status": "error", "label": "Couverture illisible", "error": str(exc), "workspace": workspace}
    coverage = manifest.get("coverage") or {}
    included = int(coverage.get("included_files") or len(manifest.get("included") or []))
    omitted = int(coverage.get("omitted_files") or len(manifest.get("omitted") or []))
    total = int(coverage.get("total_files") or (included + omitted))
    percent = coverage.get("percent")
    if percent is None:
        percent = round((included * 100.0 / total), 1) if total else 100
    status = coverage.get("status") or ("complete" if omitted == 0 else "partial")
    label = "Audit projet complet" if status == "complete" else "Audit projet incomplet"
    return {
        "status": status,
        "label": label,
        "workspace": workspace,
        "manifest": str(manifests[0]),
        "lot": manifest.get("lot", ""),
        "included_files": included,
        "omitted_files": omitted,
        "total_files": total,
        "percent": percent,
        "is_project_complete": status == "complete",
        "omitted": (manifest.get("omitted") or [])[:10],
    }


def status_label(status):
    mapping = {
        "structure-passed": "Preparation OK - audit reel requis",
        "passed": "Audit valide",
        "prepared": "Preparation prete",
        "failed": "Validation bloquee",
        "running": "Execution en cours",
    }
    return mapping.get(status, status or "En attente")


def read_last_run_status():
    artifacts = latest_artifacts()
    run_log = artifacts.get("run_log")
    if not run_log:
        return {"status": "idle", "label": "En attente", "artifacts": artifacts}
    try:
        payload = json.loads(Path(run_log).read_text(encoding="utf-8"))
        status = payload.get("status", "observed")
    except Exception:
        status = "observed"
    return {"status": status, "label": status_label(status), "artifacts": artifacts}


def run_job(job_id, command_key, project_path, confirmed=False):
    commands = build_commands(project_path)
    with JOBS_LOCK:
        job = JOBS[job_id]
        job["status"] = "running"
        job["started_at"] = now_iso()
        job["last_activity_at"] = job["started_at"]
        job["last_activity_ts"] = time.time()
        job["health"] = "active"
        job["stalled"] = False
    try:
        if command_key not in ALLOWED_COMMANDS:
            raise ValueError("Commande non autorisee.")
        item = commands[command_key]
        if item["dangerous"] and not confirmed:
            raise PermissionError("Confirmation requise pour cette action.")
        if item["template"]:
            output = item["command"]
            level = "template"
            return_code = 0
        else:
            add_log("run", item["label"], item["command"])
            process = subprocess.Popen(
                item["command"],
                cwd=str(ROOT),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                shell=True,
                bufsize=1,
            )
            with JOBS_LOCK:
                JOB_PROCESSES[job_id] = process
                job = JOBS[job_id]
                job["pid"] = process.pid
            output_parts = []
            while True:
                line = process.stdout.readline() if process.stdout else ""
                if line:
                    output_parts.append(line)
                    append_job_output(job_id, line)
                    continue
                if process.poll() is not None:
                    break
                time.sleep(0.25)
            if process.stdout:
                remaining = process.stdout.read()
                if remaining:
                    output_parts.append(remaining)
                    append_job_output(job_id, remaining)
            return_code = process.wait()
            output = "".join(output_parts)
            level = "ok" if return_code == 0 else "error"
            with JOBS_LOCK:
                JOB_PROCESSES.pop(job_id, None)
        entry = add_log(level, item["label"], output)
        with JOBS_LOCK:
            job = JOBS[job_id]
            if job.get("cancel_requested"):
                job["status"] = "canceled"
                job["health"] = "canceled"
            else:
                job["status"] = "succeeded" if return_code == 0 else "failed"
                job["health"] = "done" if return_code == 0 else "failed"
            job["finished_at"] = now_iso()
            job["return_code"] = return_code
            job["output"] = output
            job["log_entry"] = entry
    except Exception as exc:
        entry = add_log("error", "Job echoue", str(exc))
        with JOBS_LOCK:
            JOB_PROCESSES.pop(job_id, None)
            job = JOBS[job_id]
            job["status"] = "failed"
            job["health"] = "failed"
            job["finished_at"] = now_iso()
            job["return_code"] = 1
            job["output"] = str(exc)
            job["log_entry"] = entry


def create_job(command_key, project_path, confirmed=False):
    commands = build_commands(project_path)
    if command_key not in ALLOWED_COMMANDS:
        raise ValueError("Commande non autorisee.")
    item = commands[command_key]
    if item["dangerous"] and not confirmed:
        raise PermissionError("Confirmation requise pour cette action.")
    job_id = "job_" + uuid.uuid4().hex[:12]
    job = {
        "id": job_id,
        "command": command_key,
        "label": item["label"],
        "status": "queued",
        "created_at": now_iso(),
        "started_at": "",
        "finished_at": "",
        "last_activity_at": "",
        "health": "queued",
        "stalled": False,
        "silence_seconds": 0,
        "pid": None,
        "return_code": None,
        "output": "",
    }
    with JOBS_LOCK:
        JOBS[job_id] = job
    thread = threading.Thread(target=run_job, args=(job_id, command_key, project_path, confirmed), daemon=True)
    thread.start()
    return job


def create_new_project_job(payload, confirmed=False):
    run_aider = bool(payload.get("run_aider"))
    if run_aider and not confirmed:
        raise PermissionError("Confirmation requise pour cette action.")
    data, command = build_new_project_command(payload, run_aider=run_aider)
    job_id = "job_" + uuid.uuid4().hex[:12]
    job = {
        "id": job_id,
        "command": "new_project",
        "label": "Nouveau projet: " + data["project_name"],
        "status": "queued",
        "created_at": now_iso(),
        "started_at": "",
        "finished_at": "",
        "last_activity_at": "",
        "health": "queued",
        "stalled": False,
        "silence_seconds": 0,
        "pid": None,
        "return_code": None,
        "output": "",
        "target_project_path": data["target_project_path"],
    }
    with JOBS_LOCK:
        JOBS[job_id] = job
    thread = threading.Thread(target=run_dynamic_job, args=(job_id, job["label"], command), daemon=True)
    thread.start()
    return job


def run_dynamic_job(job_id, label, command):
    with JOBS_LOCK:
        job = JOBS[job_id]
        job["status"] = "running"
        job["started_at"] = now_iso()
        job["last_activity_at"] = job["started_at"]
        job["last_activity_ts"] = time.time()
        job["health"] = "active"
        job["stalled"] = False
    try:
        add_log("run", label, command)
        process = subprocess.Popen(
            command,
            cwd=str(ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            shell=True,
            bufsize=1,
        )
        with JOBS_LOCK:
            JOB_PROCESSES[job_id] = process
            JOBS[job_id]["pid"] = process.pid
        output_parts = []
        while True:
            line = process.stdout.readline() if process.stdout else ""
            if line:
                output_parts.append(line)
                append_job_output(job_id, line)
                continue
            if process.poll() is not None:
                break
            time.sleep(0.25)
        if process.stdout:
            remaining = process.stdout.read()
            if remaining:
                output_parts.append(remaining)
                append_job_output(job_id, remaining)
        return_code = process.wait()
        output = "".join(output_parts)
        entry = add_log("ok" if return_code == 0 else "error", label, output)
        with JOBS_LOCK:
            JOB_PROCESSES.pop(job_id, None)
            job = JOBS[job_id]
            if job.get("cancel_requested"):
                job["status"] = "canceled"
                job["health"] = "canceled"
            else:
                job["status"] = "succeeded" if return_code == 0 else "failed"
                job["health"] = "done" if return_code == 0 else "failed"
            job["finished_at"] = now_iso()
            job["return_code"] = return_code
            job["output"] = output
            job["log_entry"] = entry
    except Exception as exc:
        entry = add_log("error", "Job creation echoue", str(exc))
        with JOBS_LOCK:
            JOB_PROCESSES.pop(job_id, None)
            job = JOBS[job_id]
            job["status"] = "failed"
            job["health"] = "failed"
            job["finished_at"] = now_iso()
            job["return_code"] = 1
            job["output"] = str(exc)
            job["log_entry"] = entry


def cancel_job(job_id):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        process = JOB_PROCESSES.get(job_id)
        if job is None:
            raise KeyError("Job introuvable.")
        if job.get("status") not in ("queued", "running"):
            return public_job(job)
        job["cancel_requested"] = True
        job["health"] = "canceling"
        pid = job.get("pid")
    if process is not None and pid:
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            cwd=str(ROOT),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            shell=False,
        )
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if job and job.get("status") == "queued":
            job["status"] = "canceled"
            job["finished_at"] = now_iso()
            job["return_code"] = -1
    add_log("state", "Job annule", job_id)
    with JOBS_LOCK:
        return public_job(JOBS[job_id])


def run_shell_command(command_key, project_path, confirmed=False):
    commands = build_commands(project_path)
    if command_key not in ALLOWED_COMMANDS:
        raise ValueError("Commande non autorisee.")
    item = commands[command_key]
    if item["dangerous"] and not confirmed:
        raise PermissionError("Confirmation requise pour cette action.")
    if item["template"]:
        return add_log("template", item["label"], item["command"])

    add_log("run", item["label"], item["command"])
    completed = subprocess.run(
        item["command"],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        shell=True,
    )
    level = "ok" if completed.returncode == 0 else "error"
    return add_log(level, item["label"], completed.stdout)


def create_ticket_from_report(workspace_path, report_path=""):
    command = [
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "tools" / "New-AiderFixTicketFromReport.ps1"),
        "-WorkspacePath",
        workspace_path,
    ]
    if report_path:
        command.extend(["-ReportPath", report_path])
    completed = subprocess.run(
        command,
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        shell=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stdout)
    add_log("ok", "Ticket depuis rapport", completed.stdout)
    return completed.stdout


def create_app(default_project=None):
    from flask import Flask, jsonify, render_template, request, send_file

    app = Flask(__name__)

    def current_project():
        return load_state(default_project).get("audit_project_path", str(ROOT))

    def current_creation_parent():
        return load_state(default_project).get("creation_parent_path", "D:\\Dev")

    @app.route("/")
    def index():
        return render_template("index.html")

    @app.route("/api/state")
    def api_state():
        project_path = current_project()
        commands = build_commands(project_path)
        try:
            git_info = get_git_info(project_path)
        except Exception as exc:
            git_info = {"error": str(exc), "github_url": ""}
        try:
            dependencies = get_dependency_info(project_path)
        except Exception as exc:
            dependencies = {"error": str(exc)}
        return jsonify(
            {
                "project_path": project_path,
                "audit_project_path": project_path,
                "creation_parent_path": current_creation_parent(),
                "git": git_info,
                "dependencies": dependencies,
                "commands": commands,
                "workflow_steps": WORKFLOW_STEPS,
                "last_run": read_last_run_status(),
                "audit_coverage": read_audit_coverage(),
                "jobs": [public_job(job) for job in list(JOBS.values())[-20:]],
                "logs": LOGS[-80:],
            }
        )

    @app.route("/api/project", methods=["POST"])
    def api_project():
        payload = request.get_json(force=True)
        project_path = payload.get("project_path", "").strip()
        if not project_path:
            return jsonify({"error": "Chemin projet manquant."}), 400
        if not Path(project_path).exists():
            return jsonify({"error": "Le chemin projet n'existe pas."}), 400
        save_state(project_path)
        add_log("state", "Projet actif", project_path)
        return jsonify({"ok": True, "project_path": project_path})

    @app.route("/api/project/browse", methods=["POST"])
    def api_project_browse():
        try:
            import tkinter
            from tkinter import filedialog

            root = tkinter.Tk()
            root.withdraw()
            root.attributes("-topmost", True)
            selected = filedialog.askdirectory(initialdir=current_project(), title="Choisir le projet cible")
            root.destroy()
            if not selected:
                return jsonify({"ok": False, "canceled": True})
            save_state(selected)
            add_log("state", "Projet actif", selected)
            return jsonify({"ok": True, "project_path": selected})
        except Exception as exc:
            return jsonify({"error": "Selection dossier indisponible: " + str(exc)}), 400

    @app.route("/api/creation-parent", methods=["POST"])
    def api_creation_parent():
        payload = request.get_json(force=True)
        parent_path = payload.get("creation_parent_path", "").strip()
        if not parent_path:
            return jsonify({"error": "Dossier parent manquant."}), 400
        if not Path(parent_path).exists():
            return jsonify({"error": "Le dossier parent n'existe pas."}), 400
        save_creation_parent(parent_path)
        add_log("state", "Parent creation actif", parent_path)
        return jsonify({"ok": True, "creation_parent_path": parent_path})

    @app.route("/api/new-project/browse-parent", methods=["POST"])
    def api_new_project_browse_parent():
        try:
            import tkinter
            from tkinter import filedialog

            root = tkinter.Tk()
            root.withdraw()
            root.attributes("-topmost", True)
            selected = filedialog.askdirectory(initialdir=current_creation_parent(), title="Choisir le dossier parent")
            root.destroy()
            if not selected:
                return jsonify({"ok": False, "canceled": True})
            save_creation_parent(selected)
            return jsonify({"ok": True, "parent_path": selected})
        except Exception as exc:
            return jsonify({"error": "Selection dossier indisponible: " + str(exc)}), 400

    @app.route("/api/new-project/preview", methods=["POST"])
    def api_new_project_preview():
        payload = request.get_json(force=True)
        try:
            data, command = build_new_project_command(payload, run_aider=False)
            return jsonify({"ok": True, "project": data, "command_preview": command})
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/new-project", methods=["POST"])
    def api_new_project():
        payload = request.get_json(force=True)
        confirmed = bool(payload.get("confirmed"))
        try:
            job = create_new_project_job(payload, confirmed=confirmed)
            return jsonify({"ok": True, "job": job})
        except PermissionError as exc:
            return jsonify({"error": str(exc), "requires_confirmation": True}), 409
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/report")
    def api_report():
        report_path = find_report_path(request.args.get("path", ""))
        if not report_path or not report_path.exists():
            return jsonify({"error": "Aucun rapport disponible."}), 404
        text = report_path.read_text(encoding="utf-8", errors="replace")
        return jsonify(
            {
                "ok": True,
                "path": str(report_path),
                "raw": text,
                "html": render_markdown_report(text),
                "warnings": report_warnings(text),
            }
        )

    @app.route("/api/report/download")
    def api_report_download():
        report_path = find_report_path(request.args.get("path", ""))
        if not report_path or not report_path.exists():
            return jsonify({"error": "Aucun rapport disponible."}), 404
        return send_file(
            str(report_path),
            as_attachment=True,
            download_name=report_path.name,
            mimetype="text/markdown; charset=utf-8",
        )

    @app.route("/api/run", methods=["POST"])
    def api_run():
        payload = request.get_json(force=True)
        command_key = payload.get("command")
        confirmed = bool(payload.get("confirmed"))
        use_job = bool(payload.get("job"))
        try:
            if use_job:
                job = create_job(command_key, current_project(), confirmed)
                return jsonify({"ok": True, "job": job})
            entry = run_shell_command(command_key, current_project(), confirmed)
            return jsonify({"ok": True, "entry": entry})
        except PermissionError as exc:
            return jsonify({"error": str(exc), "requires_confirmation": True}), 409
        except Exception as exc:
            add_log("error", "Commande refusee", str(exc))
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/jobs", methods=["GET", "POST"])
    def api_jobs():
        if request.method == "GET":
            with JOBS_LOCK:
                jobs = [public_job(job) for job in list(JOBS.values())[-50:]]
            return jsonify({"jobs": jobs})
        payload = request.get_json(force=True)
        command_key = payload.get("command")
        confirmed = bool(payload.get("confirmed"))
        try:
            job = create_job(command_key, current_project(), confirmed)
            return jsonify({"ok": True, "job": job})
        except PermissionError as exc:
            return jsonify({"error": str(exc), "requires_confirmation": True}), 409
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/jobs/<job_id>")
    def api_job_detail(job_id):
        with JOBS_LOCK:
            job = JOBS.get(job_id)
        if job is None:
            return jsonify({"error": "Job introuvable."}), 404
        return jsonify({"job": public_job(job)})

    @app.route("/api/jobs/<job_id>/cancel", methods=["POST"])
    def api_job_cancel(job_id):
        try:
            return jsonify({"ok": True, "job": cancel_job(job_id)})
        except KeyError:
            return jsonify({"error": "Job introuvable."}), 404
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/tickets/from-report", methods=["POST"])
    def api_ticket_from_report():
        payload = request.get_json(force=True)
        artifacts = latest_artifacts()
        workspace = payload.get("workspace_path") or artifacts.get("workspace")
        report = payload.get("report_path") or artifacts.get("report")
        if not workspace:
            return jsonify({"error": "Aucun workspace disponible."}), 400
        try:
            output = create_ticket_from_report(workspace, report)
            return jsonify({"ok": True, "output": output})
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400

    @app.route("/api/chat", methods=["POST"])
    def api_chat():
        payload = request.get_json(force=True)
        message = payload.get("message", "").strip().lower()
        mapping = [
            ("audit", "audit_dry_run"),
            ("test", "tests"),
            ("git", "git_status"),
            ("diff", "git_diff"),
            ("hermes", "hermes_guidance"),
            ("aider", "aider_manual"),
        ]
        for keyword, command_key in mapping:
            if keyword in message:
                entry = run_shell_command(command_key, current_project(), confirmed=False)
                return jsonify({"ok": True, "entry": entry})
        entry = add_log(
            "chat",
            "Commande non reconnue",
            "Essayez: audit, tests, git, diff, hermes ou aider.",
        )
        return jsonify({"ok": True, "entry": entry})

    return app


def self_test(project_path):
    git_info = get_git_info(project_path)
    return {
        "kind": "controltower-flask-ui",
        "project_path": str(project_path),
        "github_url": git_info.get("github_url", ""),
        "jobs_supported": True,
        "workflow_steps": WORKFLOW_STEPS,
        "last_run": read_last_run_status(),
        "audit_coverage": read_audit_coverage(),
        "commands": build_commands(project_path),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--project-path", default=str(ROOT))
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        print(json.dumps(self_test(args.project_path), indent=2))
        return 0

    save_state(args.project_path)
    app = create_app(args.project_path)
    url = "http://{0}:{1}".format(args.host, args.port)
    if not args.no_browser:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    add_log("start", "ControlTower UI", url)
    app.run(host=args.host, port=args.port, debug=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
