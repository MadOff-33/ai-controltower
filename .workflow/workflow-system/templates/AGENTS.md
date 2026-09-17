# AGENTS.md — Règles du projet

## Chargement obligatoire

Avant toute tâche :

1. lire `.workflow/workflow-system/WORKFLOW.md` ;
2. charger `using-superpowers/SKILL.md` depuis le dossier de skills de l'agent ;
3. exécuter `.workflow/workflow-system/procedures/00-session-preflight.md` ;
4. suivre `.workflow/workflow-system/ROUTER.md` ;
5. charger réellement les `SKILL.md` sélectionnés par la route ;
6. lire `CONTEXT.md`, `.workflow/project-manifest.yaml` et `.workflow/state.yaml`.

## Workflow

Le workflow maître se trouve dans `.workflow/workflow-system/WORKFLOW.md`.

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
