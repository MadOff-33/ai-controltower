#!/usr/bin/env bash
set -euo pipefail

workflow_root="${1:-.}"
project_root="${2:-}"

required_files=(
  "WORKFLOW.md"
  "MANIFEST.yaml"
  "ROUTER.md"
  "INSTALL.md"
  "00-pre-requis.md"
  "01-installation-socle.md"
  "02-initialisation-projet.md"
  "03-workflow-universel.md"
  "04-routes-par-type-de-demande.md"
  "05-roles-et-handoffs.md"
  "06-structure-projet.md"
  "07-verification-installation.md"
  "04-contracts/spec-contract.md"
  "04-contracts/evidence-bundle.md"
  "04-contracts/review-report.md"
  "04-contracts/git-gate.md"
  "04-contracts/notion-sync-bridge.md"
  "05-adapters/codex.md"
  "05-adapters/glm.md"
  "05-adapters/claude.md"
  "procedures/00-session-preflight.md"
  "procedures/external-agent-handoff.md"
  "procedures/independent-review-gate.md"
  "procedures/git-integration-gate.md"
  "VERSION.lock"
)

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$workflow_root/$relative_path" ]]; then
    printf 'MISSING %s\n' "$relative_path"
    exit 1
  fi
done

if command -v node >/dev/null 2>&1; then
  node --version
else
  printf 'WARN node not found; install prerequisites before using BMAD\n'
fi

if command -v git >/dev/null 2>&1; then
  git --version
else
  printf 'WARN git not found; install prerequisites before using the workflow\n'
fi

if [[ -n "$project_root" ]]; then
  for relative_path in "_bmad" "_bmad-output" "AGENTS.md" ".workflow/project-manifest.yaml" ".workflow/state.yaml"; do
    if [[ ! -e "$project_root/$relative_path" ]]; then
      printf 'PROJECT MISSING %s\n' "$relative_path"
      exit 1
    fi
  done
fi

printf 'Workflow structure: OK\n'
