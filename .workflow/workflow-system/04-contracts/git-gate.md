# Contrat Git

## Règles

1. Commencer par une baseline propre et enregistrer le SHA de base.
2. Isoler le travail dans une branche ou un worktree dédié.
3. Un agent ne merge pas son propre travail.
4. Ne jamais pousser automatiquement vers `main`.
5. Chaque handoff inclut base SHA, head SHA, diff et commandes exécutées.
6. Après revue approuvée, Codex décide merge, PR ou conservation de branche.

## Commandes minimales

~~~bash
git status --short
git branch --show-current
git rev-parse HEAD
git diff --check
git log -1 --oneline
~~~

