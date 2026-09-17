# WORKFLOW.md — Point d'entrée obligatoire

## Mission

Ce dossier définit le workflow universel du projet. Il ne remplace pas les règles du dépôt : les règles du dépôt sont prioritaires.

## Ordre obligatoire avant toute demande

1. Lire `MANIFEST.yaml`.
2. Lire `ROUTER.md`.
3. Lire `AGENTS.md` et `CLAUDE.md` s'ils existent.
4. Lire `CONTEXT.md`, les ADR pertinentes et l'état du sprint.
5. Charger d'abord `using-superpowers/SKILL.md` depuis le dossier de skills de l'agent (`.agents/skills/` ou `.claude/skills/`).
6. Exécuter `procedures/00-session-preflight.md` en lecture seule.
7. Classer ou confirmer la demande : R0, R1, R2, R3, R4 ou R5.
8. Charger réellement les `SKILL.md` requis et conditionnels sélectionnés par la route avant toute action.
9. Annoncer la route, les skills chargés, les sorties attendues et le gate suivant.
10. Ne rien modifier avant le gate prévu.

## Répartition des responsabilités

- **Codex** : route, planifie, distribue, vérifie les preuves et contrôle Git.
- **GLM** : écrit le code et les tests sur une branche ou worktree dédiée.
- **Claude** : réalise la revue indépendante ; il ne modifie pas la branche d'implémentation.
- **Aider/LLM local** : exécute uniquement les tâches explicitement autorisées dans son handoff.

## Règles non négociables

- Aucun secret dans un prompt, une issue, un bundle de preuves ou un commit.
- GLM ne s'auto-approuve jamais.
- Une revue Claude ne vaut que si elle est réalisée dans un contexte indépendant.
- Toute correction après revue déclenche une nouvelle revue.
- Toute déclaration de succès doit être accompagnée d'une commande exécutée et de son résultat.
- Aucun push, merge, publication ou migration destructive sans validation explicite.
- Une seule source de vérité pour la spec et une seule source de vérité pour l'état du travail.
