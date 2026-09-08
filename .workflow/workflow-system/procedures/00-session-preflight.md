# Préflight de session

À exécuter avant de choisir une route.

1. Lire WORKFLOW.md, MANIFEST.yaml, ROUTER.md, AGENTS.md/CLAUDE.md, CONTEXT.md et les ADR pertinentes.
2. Inspecter l'état Git et la branche.
3. Identifier les commandes de test/build sans lire les secrets.
4. Relever les travaux en cours et la baseline.
5. Classer la demande R0 à R5.
6. Annoncer les skills, dépendances, sorties attendues et gate suivant.
7. S'arrêter avant toute mutation si le GO requis n'est pas explicite.

Sortie minimale :

~~~text
Type de demande:
Niveau de risque:
Route:
Contexte lu:
Baseline:
Branche/worktree:
Skills et dépendances:
Sorties:
Gate suivant:
~~~
