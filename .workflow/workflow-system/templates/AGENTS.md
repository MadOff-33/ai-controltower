# AGENTS.md — Règles du projet

## Chargement obligatoire

Avant toute tâche :

1. lire `.workflow/workflow-system/WORKFLOW.md` ;
2. charger `.agents/skills/using-superpowers/SKILL.md` ;
3. résoudre le worktree actif avant de lire `CONTEXT.md`, via la section 0 de `.workflow/workflow-system/procedures/00-session-preflight.md` ;
4. si un autre worktree est sélectionné, s'y placer et reprendre le workflow depuis son entrée ;
5. dans le worktree retenu, lire `CONTEXT.md`, `.workflow/project-manifest.yaml`, `.workflow/state.yaml` et les sources de vérité pertinentes ; pour une reprise, reconstituer ce qui a déjà été fait et ce qui reste ouvert ou incertain ;
6. suivre `.workflow/workflow-system/ROUTER.md` pour classer ou confirmer la route ;
7. charger réellement les `SKILL.md` sélectionnés par la route ;
8. terminer le préflight, puis laisser la route, les skills et les agents proposer dynamiquement la suite logique avant toute mutation.

## Workflow

Le workflow maître se trouve dans .workflow/workflow-system/WORKFLOW.md.

## Stack

- Langage : à renseigner
- Framework : à renseigner
- Base de données : à renseigner
- Gestionnaire de paquets : à renseigner

## Commandes vérifiées

~~~bash
# Installation
[à renseigner]

# Tests ciblés
[à renseigner]

# Suite complète
[à renseigner]

# Build
[à renseigner]

# Lint
[à renseigner]
~~~

## Règles

- Ne pas modifier les fichiers hors périmètre.
- Ne pas exposer de secret.
- Ne pas déclarer une tâche terminée sans preuve.
- Respecter les conventions existantes.
- Toute migration destructive nécessite une validation explicite.
