import argparse
import json
import os
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path


ROOT = Path("C:/AI_ControlTower")
APP_DIR = ROOT / "apps" / "controltower-ui"
STATE_PATH = APP_DIR / "state.json"
LOG_LIMIT = 300
LOGS = []
LOG_LOCK = threading.Lock()


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
        try:
            entry = run_shell_command(command_key, current_project(), confirmed)
            return jsonify({"ok": True, "entry": entry})
        except PermissionError as exc:
            return jsonify({"error": str(exc), "requires_confirmation": True}), 409
        except Exception as exc:
            add_log("error", "Commande refusee", str(exc))
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
