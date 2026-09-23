# 03 — Workflow universel

## Phase 0 — Préflight systématique

Procédure du workflow : procedures/00-session-preflight.md.

~~~text
Lire WORKFLOW.md
→ résoudre le worktree actif
→ lire MANIFEST.yaml / ROUTER.md / AGENTS.md / CLAUDE.md
→ lire le contexte et les sources de vérité pertinentes
→ reconstituer l'état réel si la demande est une reprise
→ git status et baseline
→ classer ou confirmer la demande
→ charger les skills de la route
→ laisser le workflow proposer dynamiquement la suite
~~~

Sortie obligatoire :

~~~text
Type de demande:
Niveau de risque:
Route sélectionnée:
Contexte repris:
État actuel reconstitué:
Fichiers sensibles exclus:
Branche de travail:
Skills chargés:
Suite proposée par le workflow:
Sorties attendues:
Gate suivant:
~~~

## Phase 1 — Clarification

Utiliser l'un des chemins suivants :

- demande claire et bornée : validation courte ;
- demande floue : Matt grill-with-docs ;
- idée produit : BMAD bmad-product-brief ou Matt prototype ;
- décision technique : Matt domain-modeling et codebase-design ;
- recherche : Matt research ou BMAD bmad-deep-recon.

## Phase 2 — Contrat de travail

La demande doit aboutir à une spec, un ticket ou une décision explicite.

- R2 : contrat court dans la conversation ou dans une issue ;
- R3 : Matt to-spec, puis to-tickets ;
- R4 : BMAD bmad-prd, bmad-spec, architecture et stories.

## Phase 3 — Plan

Utiliser Superpowers writing-plans pour toute implémentation multi-fichiers ou à risque.

Le plan doit préciser :

- fichiers à créer ou modifier ;
- interfaces ;
- tests ;
- commandes de vérification ;
- risques ;
- critères d'acceptation ;
- agent responsable ;
- conditions d'arrêt.

## Phase 4 — Isolation

Utiliser Superpowers using-git-worktrees avant l'implémentation, sauf décision explicite de travailler dans la branche courante.

La branche GLM doit être distincte de main.

## Phase 5 — Implémentation

Créer un handoff court pour GLM :

~~~text
Contexte:
Mission:
Contraintes critiques:
Fichiers autorisés:
Tests obligatoires:
Commandes de vérification:
Livrables:
~~~

GLM applique le TDD et retourne un evidence bundle. Il ne prononce pas l'approbation finale.

## Phase 6 — Revue indépendante

Claude reçoit uniquement :

- la spec ou le ticket ;
- le diff ;
- les résultats de tests ;
- le contexte projet pertinent ;
- les règles de revue.

Claude retourne :

~~~text
APPROVED
ou
CHANGES_REQUIRED
~~~

Chaque finding doit avoir une sévérité, une preuve, une action attendue et un statut.

## Phase 7 — Vérification et intégration

Codex doit utiliser Superpowers verification-before-completion avant toute déclaration de succès.

Puis :

~~~text
vérifier le diff
→ vérifier les tests indépendamment
→ vérifier l'absence de secret
→ vérifier le bundle de preuves
→ vérifier le statut de revue
→ merge ou PR selon décision humaine
~~~

Après correction d'un finding, la revue Claude est relancée.
