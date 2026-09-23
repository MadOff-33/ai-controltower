# 02 — Initialisation propre du projet

Cette procédure est exécutée une seule fois par projet, avant la première demande de développement.

## Étape 1 — Créer les dossiers de base

~~~
cd /home/mike/workspace/<nom-projet>
mkdir -p docs/adr docs/research docs/specs docs/plans docs/reviews
mkdir -p _workflow-artifacts/evidence _workflow-artifacts/handoffs
mkdir -p .workflow
touch README.md AGENTS.md .gitignore .workflow/state.yaml
~~~

## Étape 2 — Inventaire en lecture seule

Codex doit lire et consigner :

~~~
- branche et remote Git ;
- structure du dépôt ;
- AGENTS.md et CLAUDE.md ;
- technologies et versions ;
- commandes de build et de test ;
- fichiers de configuration ;
- état des tests existants ;
- intégrations externes ;
- risques et données sensibles ;
- présence éventuelle d'un déploiement automatique.
~~~

Ne jamais afficher le contenu des fichiers .env, clés privées ou credentials.

## Étape 3 — Créer le manifest projet

Copier templates/project-manifest.yaml vers :

~~~
.workflow/project-manifest.yaml
~~~

Compléter les champs réels. Ne pas inventer une commande de test.

## Étape 4 — Créer le contexte

Créer :

~~~
CONTEXT.md
docs/adr/
~~~

CONTEXT.md contient le vocabulaire métier et les contraintes stables. Les décisions techniques difficiles à inverser vont dans docs/adr.

## Étape 5 — Configurer AGENTS.md

Copier le modèle templates/AGENTS.md vers la racine du projet, puis renseigner les commandes et les règles spécifiques.

## Étape 6 — Définir l'état initial

Dans .workflow/state.yaml :

~~~yaml
project_status: initialized
current_route: null
current_request: null
current_branch: main
current_gate: preflight
last_verified_commit: null
open_findings: []
~~~

## Étape 7 — Baseline technique

Exécuter les commandes détectées pendant l'inventaire :

~~~
git status --short
<commande-de-test-du-projet>
<commande-de-build-du-projet-si-elle-existe>
~~~

Si la baseline échoue, ne pas commencer une fonctionnalité. Créer une route R5 et documenter l'échec.

## Étape 8 — Commit d'initialisation

Après vérification :

~~~
git add AGENTS.md CONTEXT.md .gitignore .workflow docs README.md _workflow-artifacts
git commit -m "chore: initialize universal ai workflow"
~~~

Le commit d'initialisation doit être séparé du premier changement fonctionnel.
