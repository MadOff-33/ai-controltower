import argparse
import json
import os
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
    state = {"last_project_path": str(default_project or ROOT)}
    if STATE_PATH.exists():
        try:
            loaded = json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if loaded.get("last_project_path"):
                state["last_project_path"] = loaded["last_project_path"]
        except Exception:
            pass
    return state


def save_state(project_path):
    STATE_PATH.write_text(
        json.dumps({"last_project_path": str(project_path)}, indent=2),
        encoding="utf-8",
    )


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
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Install-ControlTower.ps1"',
        },
        "audit_dry_run": {
            "label": "Audit dry-run",
            "group": "Audit",
            "dangerous": False,
            "template": False,
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath '
            + project
            + " -ValidateAfterDryRun",
        },
        "audit_real": {
            "label": "Audit reel avec Aider",
            "group": "Audit",
            "dangerous": True,
            "template": False,
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath '
            + project
            + " -RunAider",
        },
        "continue_audit": {
            "label": "Continuer audit",
            "group": "Audit",
            "dangerous": True,
            "template": False,
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Invoke-AiderAuditContinuation.ps1" -WorkspacePath '
            + latest_workspace_arg
            + " -RunAider",
        },
        "fix_dry_run": {
            "label": "Fix dry-run depuis ticket",
            "group": "Correction",
            "dangerous": False,
            "template": True,
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
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\tests\\Invoke-ControlTowerTestSuite.ps1"',
        },
        "final_recipe": {
            "label": "Recette finale projet",
            "group": "Qualite",
            "dangerous": False,
            "template": False,
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Test-ControlTowerFinalRecipe.ps1" -ProjectPath '
            + project
            + " -SkipFullSuite",
        },
        "hermes_guidance": {
            "label": "Guidance Hermes",
            "group": "Memoire",
            "dangerous": False,
            "template": False,
            "command": 'powershell -ExecutionPolicy Bypass -File "C:\\AI_ControlTower\\tools\\Get-HermesGuidance.ps1"',
        },
        "git_status": {
            "label": "Git status",
            "group": "Git",
            "dangerous": False,
            "template": False,
            "command": "git -C " + project + " status",
        },
        "git_diff": {
            "label": "Git diff",
            "group": "Git",
            "dangerous": False,
            "template": False,
            "command": "git -C " + project + " diff",
        },
        "aider_manual": {
            "label": "Aider manuel cadre",
            "group": "Aider",
            "dangerous": True,
            "template": False,
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
    from flask import Flask, jsonify, render_template, request

    app = Flask(__name__)

    def current_project():
        return load_state(default_project).get("last_project_path", str(ROOT))

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
