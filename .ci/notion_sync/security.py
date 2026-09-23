#!/usr/bin/env python3
"""
security.py — Garde-fous de confidentialité (identiques à Notion_Knowledge_OS).

- On ne lit JAMAIS la valeur d'un .env/secret : on détecte la PRÉSENCE.
- Tout champ au nom interdit est masqué : [SECRET REDACTED].
- Toute valeur ressemblant à un secret / email est masquée.
"""
from __future__ import annotations
import re
from typing import Any, List, Tuple

REDACTED = "[SECRET REDACTED]"

FORBIDDEN_FIELD_NAMES = {
    "password", "passwd", "pwd", "token", "access_token", "refresh_token",
    "secret", "client_secret", "consumer_secret", "api_key", "apikey",
    "api_secret", "private_key", "privatekey", "credential", "credentials",
    "authorization", "auth_token", "session_key", "encryption_key",
}

SENSITIVE_FILE_PATTERNS = [
    r"^\.env($|\..+)", r".*\.env$", r".*\.env\.bak.*",
    r".*\.pem$", r".*\.key$", r".*\.p12$", r".*\.pfx$",
    r"^id_rsa$", r"^id_ed25519$",
    r".*credentials.*\.json$", r".*service[-_]account.*\.json$",
    r"^settings\.json$", r"^secrets?\.ya?ml$",
]

VALUE_SECRET_PATTERNS = [
    re.compile(r"AKIA[0-9A-Z]{16}"),
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"ghp_[A-Za-z0-9]{20,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"secret_[A-Za-z0-9]{20,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"),
]
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}")


def is_forbidden_field(name: str) -> bool:
    n = re.sub(r"[^a-z0-9]", "_", str(name).lower())
    return n in FORBIDDEN_FIELD_NAMES or any(b in n for b in FORBIDDEN_FIELD_NAMES)


def looks_like_secret_value(v: str) -> bool:
    return isinstance(v, str) and any(p.search(v) for p in VALUE_SECRET_PATTERNS)


def redact_value(v: Any) -> Any:
    if not isinstance(v, str):
        return v
    if looks_like_secret_value(v):
        return REDACTED
    if EMAIL_RE.search(v):
        return EMAIL_RE.sub(REDACTED, v)
    return v


def sanitize(obj: Any, report: List[str] | None = None, path: str = "") -> Tuple[Any, List[str]]:
    report = report if report is not None else []
    if isinstance(obj, dict):
        clean = {}
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if is_forbidden_field(k):
                clean[k] = REDACTED
                report.append(p)
                continue
            clean[k], _ = sanitize(v, report, p)
        return clean, report
    if isinstance(obj, list):
        return [sanitize(v, report, f"{path}[{i}]")[0] for i, v in enumerate(obj)], report
    new = redact_value(obj)
    if new != obj:
        report.append(path or "<value>")
    return new, report
