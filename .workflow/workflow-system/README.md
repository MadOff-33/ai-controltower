# AI Workflow Universel

Dossier d'installation et d'utilisation d'un workflow de développement assisté par IA combinant :

- BMAD pour l'analyse, les exigences, l'architecture et le suivi projet ;
- Matt Pocock pour le cadrage léger, le domaine, les tickets et le diagnostic ;
- Superpowers pour les plans, l'isolation Git, le TDD et la vérification ;
- Codex comme orchestrateur ;
- GLM comme implémenteur ;
- Claude comme relecteur indépendant.

## Règle d'entrée

Avant chaque demande de développement, l'agent doit lire :

1. `WORKFLOW.md` ;
2. `MANIFEST.yaml` ;
3. `ROUTER.md` ;
4. `AGENTS.md` ou `CLAUDE.md` du projet ;
5. le contexte et l'état Git du projet.

Aucune modification de code ne commence avant la classification de la demande et la validation du niveau de procédure requis.

## Donner le workflow à un LLM

Oui : le dossier complet peut être transmis comme un seul contexte documentaire. Pour un projet actif, la procédure recommandée est de le copier dans .workflow/workflow-system/, puis de demander au LLM de charger seulement WORKFLOW.md, MANIFEST.yaml, ROUTER.md, le manifest projet et l'adaptateur de son rôle. Les procédures et contrats sont chargés ensuite selon la route.

## Lecture recommandée

1. `INSTALL.md` pour l'installation opérateur ;
2. `00-pre-requis.md`
3. `01-installation-socle.md`
4. `02-initialisation-projet.md`
5. `03-workflow-universel.md`
6. `04-routes-par-type-de-demande.md`
7. `05-roles-et-handoffs.md`
8. `06-structure-projet.md`
9. `07-verification-installation.md`

## Sources officielles

- [Matt Pocock Skills](https://github.com/mattpocock/skills)
- [BMAD Method](https://docs.bmad-method.org/)
- [BMAD installation](https://docs.bmad-method.org/fr/how-to/install-bmad/)
- [BMAD testing / TEA](https://docs.bmad-method.org/fr/reference/testing/)
- [Superpowers](https://github.com/obra/superpowers)
