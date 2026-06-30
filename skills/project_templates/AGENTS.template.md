# AGENTS.md — Règles agent projet

Ce fichier définit les règles applicables aux agents IA dans ce dépôt.

## Règles absolues

- Lire le contexte projet avant toute modification.
- Proposer un plan court avant d'écrire.
- Ne modifier que les fichiers nécessaires.
- Ne jamais lire, copier ou modifier les secrets.
- Ne jamais modifier .env, clés API, credentials, tokens ou clés SSH.
- Ne jamais faire de git push sans GO explicite.
- Ne jamais toucher à la production sans GO explicite.
- Ne jamais lancer de commande destructive sans validation humaine.

## Workflow attendu

1. Vérifier git status.
2. Lire .agent/PROJECT_CONTEXT.md.
3. Lire .agent/PROJECT_RULES.md.
4. Lire .agent/skills.lock.md.
5. Proposer un plan.
6. Modifier petit.
7. Afficher le diff.
8. Lancer les tests.
9. Commit uniquement après validation.

## Usage Aider recommandé

Commande recommandée :

aider --model ollama_chat/ornith:9b --no-auto-commits --no-dirty-commits

Les règles globales doivent être ajoutées en lecture seule.
