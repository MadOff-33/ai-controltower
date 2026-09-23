# Installation pas à pas

Ce fichier est le parcours opérateur. Les fichiers `WORKFLOW.md`, `MANIFEST.yaml` et `ROUTER.md` sont la référence comportementale du workflow.

## 0. Préparer WSL2

Dans Ubuntu WSL2 :

~~~bash
mkdir -p /home/mike/workspace
cd /home/mike/workspace
node --version
npm --version
git --version
python3 --version
uv --version
~~~

Node.js doit être en version 20.12 ou supérieure pour BMAD. Si une commande manque, installe-la avant de continuer. Utilise une version stable de BMAD, pas `next`, sauf besoin explicite.

## 1. Placer le dossier du workflow

Dépose le dossier `AI-WORKFLOW-UNIVERSEL` dans un emplacement stable, par exemple `/home/mike/workspace/AI-WORKFLOW-UNIVERSEL`.

Le dossier peut être versionné séparément. Dans chaque projet, il sert de référence documentaire ; les installations BMAD et Superpowers restent dans les emplacements natifs attendus par les agents.

Pour tes projets existants dans D:/REPO CLONES, l'automatisation GitHub ↔ Notion reste inchangée. Le pont et la règle de synchronisation sont décrits dans 04-contracts/notion-sync-bridge.md.

## 2. Installer BMAD

Depuis le projet cible :

~~~bash
cd /home/mike/workspace/<nom-projet>
npx bmad-method install
~~~

Dans l'assistant :

1. choisir la version stable ;
2. installer le module BMM ;
3. sélectionner la langue française si disponible ;
4. conserver `_bmad/` et `_bmad-output/` ;
5. ajouter TEA seulement pour les projets à risque élevé, complexes ou soumis à une exigence QA forte ;
6. accepter les outils réellement disponibles ;
7. vérifier qu'aucun ancien workflow BMAD n'est installé en parallèle.

Vérifier :

~~~bash
test -d _bmad
test -d _bmad-output
find _bmad -maxdepth 2 -type f | sort | head -80
~~~

## 3. Installer les skills de Matt Pocock

Toujours depuis le projet cible :

~~~bash
npx skills@latest add mattpocock/skills
~~~

Sélectionner au minimum :

- `grill-with-docs` ;
- `domain-modeling` ;
- `to-spec` ;
- `to-tickets` ;
- `implement` ;
- `code-review` ;
- `tdd`.

Puis exécuter une seule fois la configuration du dépôt :

~~~text
/setup-matt-pocock-skills
~~~

Si l'installation est faite pour un agent non interactif, reprendre les instructions de `05-adapters/` et les placer dans sa configuration système ou projet. Ne pas installer plusieurs copies concurrentes des mêmes skills.

## 4. Installer Superpowers

Pour Codex ou Claude, utiliser l'installation native documentée par le dépôt officiel Superpowers. Pour un agent Markdown comme Aider ou GLM, copier les instructions portables utiles dans sa configuration système ou projet.

Le noyau retenu est :

~~~text
using-superpowers
brainstorming
writing-plans
using-git-worktrees
test-driven-development
systematic-debugging
verification-before-completion
requesting-code-review
finishing-a-development-branch
~~~

Ne pas activer automatiquement `subagent-driven-development` : il est remplacé ici par le handoff vers GLM et la revue indépendante Claude.

## 5. Installer les contrats du workflow

Depuis le dossier du workflow, copier les modèles dans le projet :

~~~bash
WORKFLOW_SRC=/home/mike/workspace/AI-WORKFLOW-UNIVERSEL
cd /home/mike/workspace/<nom-projet>
mkdir -p .workflow
if [[ ! -d .workflow/workflow-system ]]; then cp -R "$WORKFLOW_SRC" .workflow/workflow-system; fi
cp "$WORKFLOW_SRC/templates/AGENTS.md" ./AGENTS.md
cp "$WORKFLOW_SRC/templates/project-manifest.yaml" ./.workflow/project-manifest.yaml
test -e .gitignore || cp "$WORKFLOW_SRC/templates/gitignore.workflow" ./.gitignore
~~~

Si `AGENTS.md` ou `.workflow/project-manifest.yaml` existe déjà, fusionner manuellement après sauvegarde ; ne pas l'écraser aveuglément.

## 6. Initialiser le projet

Suivre intégralement `02-initialisation-projet.md` :

~~~bash
mkdir -p docs/adr docs/research docs/specs docs/plans docs/reviews
mkdir -p _workflow-artifacts/evidence _workflow-artifacts/handoffs
mkdir -p .workflow
touch README.md CONTEXT.md .gitignore .workflow/state.yaml
~~~

Renseigner ensuite le manifest, les commandes de test/build, les contraintes métier et les règles d'accès des agents.

## 7. Vérifier la baseline

Avant toute demande fonctionnelle :

~~~bash
git status --short
git branch --show-current
git log -1 --oneline
<commande-de-test-du-projet>
<commande-de-build-du-projet-si-elle-existe>
~~~

Une baseline en échec devient une demande R5 de diagnostic. Elle ne doit pas être masquée par une nouvelle feature.

## 8. Créer le commit d'initialisation

Après la vérification :

~~~bash
git add AGENTS.md CONTEXT.md .gitignore .workflow docs README.md _workflow-artifacts
git commit -m "chore: initialize universal ai workflow"
~~~

Ce commit doit précéder toute branche de fonctionnalité.

## 9. Premier message à Codex

Utiliser un message court :

~~~text
Lis .workflow/workflow-system/WORKFLOW.md, .workflow/workflow-system/MANIFEST.yaml, .workflow/workflow-system/ROUTER.md et .workflow/project-manifest.yaml.
Inspecte le dépôt en lecture seule, établis la baseline et propose la route adaptée.
Ne modifie aucun fichier avant mon GO explicite.
~~~

Codex doit s'arrêter après la proposition de route et du plan. Le développement commence seulement après validation explicite.

## 10. Test de fumée de l'installation

Exécuter :

~~~bash
test -f AGENTS.md
test -f CONTEXT.md
test -f .workflow/project-manifest.yaml
test -f .workflow/state.yaml
test -d _bmad
test -d _bmad-output
test -d docs/adr
test -d docs/research
git status --short
~~~

Si toutes les commandes réussissent et que le dépôt est propre, l'installation est prête.
