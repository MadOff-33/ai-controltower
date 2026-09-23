# WORKFLOW.md — Point d'entrée obligatoire

## Mission

Ce dossier définit le workflow universel du projet. Il ne remplace pas les règles du dépôt : les règles du dépôt sont prioritaires.

## Ordre obligatoire avant toute demande

1. Lire ce `WORKFLOW.md` dans le checkout depuis lequel la session a été ouverte.
2. Charger `using-superpowers/SKILL.md` depuis le dossier de skills de l'agent (`.agents/skills/` ou `.claude/skills/`).
3. **Avant de lire `CONTEXT.md`, `.workflow/state.yaml`, les ADR ou le sprint**, exécuter la section « Résolution obligatoire du worktree actif » de `procedures/00-session-preflight.md`.
4. Si un autre worktree est sélectionné, se placer dans ce worktree et **reprendre cet ordre depuis l'étape 1**. Ne pas utiliser le contexte métier du worktree de départ.
5. Dans le worktree retenu, lire `MANIFEST.yaml`, `ROUTER.md`, `AGENTS.md` et `CLAUDE.md` s'ils existent.
6. Lire ensuite `CONTEXT.md`, `.workflow/state.yaml` et les sources de vérité pertinentes déjà disponibles dans le projet (ADR, specs, plans, tickets, historique Git, artefacts ou suivi externe référencé).
7. Si la demande est une reprise de projet, reconstituer l'état réel à partir de ces sources : ce qui a déjà été fait, ce qui reste ouvert ou incertain, et le dernier état explicitement validé. Ne pas inventer de roadmap ni déduire qu'un projet est terminé du seul fait qu'un livrable est livré.
8. Terminer `procedures/00-session-preflight.md`, notamment le contrôle runtime et la baseline Git.
9. Classer ou confirmer la demande : R0, R1, R2, R3, R4 ou R5.
10. Charger réellement les `SKILL.md` requis et conditionnels sélectionnés par la route avant toute action.
11. En reprise, laisser la route, les skills et les agents déterminer dynamiquement la suite logique à proposer à partir de l'état reconstitué.
12. Une demande de reprise est d'abord une phase de reconstruction et de proposition : elle ne déclenche aucune nouvelle action technique avant que la suite déterminée par le workflow ait été présentée à l'utilisateur.
13. Annoncer le worktree retenu, la route, les skills chargés, l'état repris, la suite proposée par le workflow et le gate suivant.
14. Ne rien modifier avant le gate prévu.

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
- Un projet ou POC n'est déclaré terminé que sur déclaration explicite de l'utilisateur ; un agent ne déduit jamais cette clôture d'un livrable, d'un commit, d'une PR ou de tests réussis.
- Une session de reprise ne doit jamais supposer que le checkout courant est le worktree actif : elle doit le vérifier avant de lire le contexte métier.
