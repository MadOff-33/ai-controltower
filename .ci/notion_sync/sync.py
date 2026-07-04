#!/usr/bin/env python3
"""
sync.py — Synchronisation INCRÉMENTALE du projet vers Notion (Knowledge OS).

Conçu pour tourner dans GitHub Actions (indépendant du PC de Michael).

Principes :
  * Mise à jour par CLÉ : chaque entité a une clé stable ("cjd-dev::risk:...").
    On cherche la page par sa clé -> si elle existe on met à jour, sinon on crée.
    => jamais de doublon, jamais de réécriture complète, on pousse les diffs.
  * Sécurité : présence des .env/secrets détectée, jamais leur contenu ; champs
    interdits masqués ; décisions sensibles créées en "À valider".
  * Champs "create-only" : le Statut des décisions et risques n'est écrit qu'à la
    création. Si tu valides une décision ou fermes un risque DANS Notion, la
    synchro ne l'écrase pas.
  * Journal : une ligne par exécution (qui / quand / commit / déclencheur / résultat).

Env :
  NOTION_TOKEN   (secret) — jeton d'intégration interne Notion. Sans lui : DRY-RUN.
  DRY_RUN        "true"/"false" (défaut : true si pas de token, false sinon)
  GITHUB_ACTOR / GITHUB_SHA / GITHUB_EVENT_NAME — fournis par GitHub Actions.
"""
from __future__ import annotations

import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

import security

try:
    import requests
except ImportError:
    requests = None

ROOT = Path(__file__).resolve().parents[2]          # racine du repo
HERE = Path(__file__).resolve().parent
MANIFEST = ROOT / "project_manifest.yaml"
DBCONF = HERE / "notion_databases.yml"

NOTION_VERSION = "2022-06-28"
API = "https://api.notion.com/v1"
MAXLEN = 1900


# --------------------------------------------------------------------------- #
# Utilitaires
# --------------------------------------------------------------------------- #
def load_yaml(p: Path) -> dict:
    with open(p, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def git(*args) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(ROOT), *args],
            stderr=subprocess.DEVNULL, text=True, timeout=15).strip()
    except Exception:
        return ""


def git_context() -> dict:
    sha = os.environ.get("GITHUB_SHA") or git("rev-parse", "HEAD")
    actor = os.environ.get("GITHUB_ACTOR") or git("log", "-1", "--pretty=%an")
    event = os.environ.get("GITHUB_EVENT_NAME", "manuel")
    trigger = {"push": "push", "schedule": "schedule",
               "workflow_dispatch": "manuel"}.get(event, "manuel")
    return {
        "branch": git("rev-parse", "--abbrev-ref", "HEAD") or "main",
        "sha": (sha or "")[:10],
        "message": git("log", "-1", "--pretty=%s"),
        "author": actor or "inconnu",
        "trigger": trigger,
    }


def detect_sensitive_files() -> list[str]:
    """PRÉSENCE uniquement — jamais de lecture de contenu."""
    pats = [re.compile(p) for p in security.SENSITIVE_FILE_PATTERNS]
    skip = {".git", "node_modules", ".venv", "venv", "__pycache__",
            "dist", "build", "dist_final"}
    found = []
    for f in ROOT.rglob("*"):
        if not f.is_file():
            continue
        if any(part in skip for part in f.parts):
            continue
        if any(p.match(f.name) for p in pats):
            found.append(str(f.relative_to(ROOT)).replace("\\", "/"))
    return sorted(set(found))


def t(s: str) -> str:
    return ("" if s is None else str(s))[:MAXLEN]


# ----- constructeurs de valeurs de propriété Notion ------------------------ #
def p_title(v): return {"title": [{"text": {"content": t(v)}}]}
def p_text(v): return {"rich_text": [{"text": {"content": t(v)}}]}
def p_select(v): return {"select": {"name": t(v)}} if v else {"select": None}
def p_multi(vs): return {"multi_select": [{"name": t(x)} for x in (vs or [])]}
def p_check(b): return {"checkbox": bool(b)}
def p_date(v): return {"date": {"start": str(v)}} if v else {"date": None}
def p_rel(pid): return {"relation": [{"id": pid}] if pid else []}


# --------------------------------------------------------------------------- #
# Client Notion
# --------------------------------------------------------------------------- #
class Notion:
    def __init__(self, token: str, dbs: dict, dry_run: bool):
        self.token = token
        self.dbs = dbs
        self.dry_run = dry_run
        self.session = requests.Session() if requests else None
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        }

    def _find(self, db_id: str, key: str) -> str | None:
        r = self.session.post(
            f"{API}/databases/{db_id}/query",
            headers=self.headers,
            json={"filter": {"property": "Clé", "rich_text": {"equals": key}},
                  "page_size": 1},
            timeout=30)
        r.raise_for_status()
        res = r.json().get("results", [])
        return res[0]["id"] if res else None

    def upsert(self, db_key: str, key: str, props: dict,
               create_only: dict | None = None, children: list | None = None) -> str:
        """Crée ou met à jour une page identifiée par sa Clé. Retourne l'ID."""
        db_id = self.dbs[db_key]
        props = dict(props)
        props["Clé"] = p_text(key)
        create_only = create_only or {}

        if self.dry_run:
            print(f"  [DRY] {db_key:<10} {key}")
            return f"dry::{key}"

        page_id = self._find(db_id, key)
        if page_id:                                   # UPDATE (diffs seulement)
            r = self.session.patch(
                f"{API}/pages/{page_id}",
                headers=self.headers, json={"properties": props}, timeout=30)
            r.raise_for_status()
            print(f"  [MAJ] {db_key:<10} {key}")
            return page_id
        # CREATE (avec les champs create-only + contenu)
        payload = {"parent": {"database_id": db_id},
                   "properties": {**props, **create_only}}
        if children:
            payload["children"] = children
        r = self.session.post(f"{API}/pages", headers=self.headers,
                              json=payload, timeout=30)
        r.raise_for_status()
        print(f"  [NEW] {db_key:<10} {key}")
        return r.json()["id"]


def para(text: str) -> dict:
    return {"object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"text": {"content": t(text)}}]}}


# --------------------------------------------------------------------------- #
# Programme principal
# --------------------------------------------------------------------------- #
def main() -> int:
    token = os.environ.get("NOTION_TOKEN", "").strip()
    dry_env = os.environ.get("DRY_RUN", "").strip().lower()
    dry_run = (dry_env == "true") or (dry_env != "false" and not token)

    if not token and not dry_run:
        sys.exit("NOTION_TOKEN manquant.")
    if not dry_run and requests is None:
        sys.exit("Le module 'requests' est requis pour un envoi réel.")

    m = load_yaml(MANIFEST)
    dbs = load_yaml(DBCONF)
    pid = m["id"]
    gc = git_context()
    sensitive = detect_sensitive_files()

    mode = "DRY-RUN (aucun envoi)" if dry_run else "RÉEL"
    print(f"== Notion sync : {m['name']} == mode={mode} "
          f"trigger={gc['trigger']} commit={gc['sha']} par {gc['author']}")
    print(f"   Fichiers sensibles détectés (présence) : {sensitive or 'aucun'}")

    n = Notion(token, dbs, dry_run)
    now = dt.datetime.now(dt.timezone.utc).astimezone().isoformat()
    result, details = "ok", []

    try:
        # ---- Projet ---------------------------------------------------------
        proj_props = {
            "Nom": p_title(m["name"]),
            "Statut": p_select(m.get("status", "active")),
            "Catégorie": p_select(m.get("category", "autre")),
            "Owner": p_text(m.get("owner", "")),
            "Description": p_text(" ".join(str(m.get("description", "")).split())),
            "Stack": p_text(", ".join(m.get("stack", []))),
            "Commandes de lancement": p_text(" ; ".join(m.get("launch_commands", []))),
            "Tests": p_text(" ; ".join(m.get("test_commands", []))),
            "Branche": p_text(gc["branch"]),
            "Source": p_text((m.get("repo", {}) or {}).get("path", "")),
            "Dernière synchro": p_date(now[:10]),
            "Dernier commit": p_text(f"{gc['sha']} — {gc['message']}"),
            "Dernier auteur": p_text(gc["author"]),
        }
        proj_props, _ = security.sanitize(proj_props)
        proj_id = n.upsert("projects", f"{pid}::project", proj_props,
                           children=[para(m.get("description", ""))])
        rel = p_rel(proj_id if not dry_run else None)

        # ---- Décisions (Statut create-only) --------------------------------
        for d in m.get("decisions", []):
            props = {"Titre": p_title(d["title"]), "Projet": rel,
                     "Sensible": p_check(d.get("sensitive", False)),
                     "Cible": p_text(d.get("target", ""))}
            props, _ = security.sanitize(props)
            n.upsert("decisions", f"{pid}::decision:{d['key']}", props,
                     create_only={"Statut": p_select(d.get("status", "À valider"))})

        # ---- Risques (Statut create-only) + auto env-backup ----------------
        risks = list(m.get("risks", []))
        if any(".env.bak" in f for f in sensitive):
            risks.append({"key": "env-backup-in-repo",
                          "title": "Sauvegardes .env.bak_* présentes dans le repo",
                          "severity": "high", "status": "open"})
        for r in risks:
            props = {"Titre": p_title(r["title"]), "Projet": rel,
                     "Sévérité": p_select(r.get("severity", "medium"))}
            props, _ = security.sanitize(props)
            n.upsert("risks", f"{pid}::risk:{r['key']}", props,
                     create_only={"Statut": p_select(r.get("status", "open"))})

        # ---- Modules IA -----------------------------------------------------
        for a in m.get("ai_modules", []):
            props = {"Titre": p_title(a["name"]), "Projet": rel,
                     "Type": p_select("ai_module"),
                     "Criticité": p_select(a.get("criticality", "normal"))}
            props, _ = security.sanitize(props)
            n.upsert("procedures", f"{pid}::aimodule:{a['key']}", props,
                     children=[para(f"Rôle : {a.get('role','')}")])

        # ---- Prompt de reprise ---------------------------------------------
        if m.get("resume_prompt"):
            props = {"Titre": p_title("Prompt de reprise"), "Projet": rel,
                     "Type": p_select("prompt"), "Criticité": p_select("critique")}
            props, _ = security.sanitize(props)
            n.upsert("procedures", f"{pid}::prompt:resume", props,
                     children=[para(m["resume_prompt"])])

        # ---- Sprints --------------------------------------------------------
        for s in m.get("sprints", []):
            props = {"Titre": p_title(s.get("title", s["key"])), "Projet": rel,
                     "Sprint": p_text(s.get("sprint", "")),
                     "Date": p_date(str(s.get("date", ""))[:10]),
                     "Résumé": p_text(" ".join(str(s.get("summary", "")).split()))}
            props, _ = security.sanitize(props)
            n.upsert("sprints", f"{pid}::sprint:{s['key']}", props)

        # ---- Accès (présence seulement) ------------------------------------
        acc = {"Titre": p_title(f"Accès — {m['name']}"), "Projet": rel,
               "Note": p_text("Présence détectée uniquement — aucune valeur lue "
                              "ni stockée."),
               "Fichiers sensibles détectés": p_text(", ".join(sensitive) or "aucun")}
        acc, _ = security.sanitize(acc)
        n.upsert("access", f"{pid}::access", acc)

    except Exception as e:                             # pragma: no cover
        result = "échec"
        details.append(str(e))
        print(f"!! Erreur : {e}")

    # ---- Journal (une ligne par run) ---------------------------------------
    if not dry_run:
        try:
            jrow = {
                "Titre": p_title(f"Sync {gc['sha']} — {gc['trigger']}"),
                "Projet": p_rel(proj_id) if 'proj_id' in dir() else p_rel(None),
                "Date": p_date(now[:10]),
                "Auteur": p_text(gc["author"]),
                "Commit": p_text(f"{gc['sha']} — {gc['message']}"),
                "Déclencheur": p_select(gc["trigger"]),
                "Résultat": p_select(result),
                "Détails": p_text("; ".join(details) or "Synchro terminée."),
                "Clé": p_text(f"{pid}::journal:{gc['sha']}"),
            }
            n.session.post(f"{API}/pages", headers=n.headers,
                           json={"parent": {"database_id": dbs["journal"]},
                                 "properties": jrow}, timeout=30).raise_for_status()
            print("   Journal mis à jour.")
        except Exception as e:
            print(f"   (journal non écrit : {e})")

    print(f"== Terminé : {result} ==")
    return 0 if result == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
