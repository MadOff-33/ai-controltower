# AGENTS.md — Règles du projet

## Chargement obligatoire

Avant toute tâche :

1. lire ce fichier ;
2. lire CONTEXT.md ;
3. lire .workflow/project-manifest.yaml ;
4. lire .workflow/state.yaml ;
5. exécuter le preflight en lecture seule.

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
