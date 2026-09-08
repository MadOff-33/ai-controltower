# 07 — Vérification de l'installation

## Vérification des logiciels

~~~bash
node --version
npm --version
git --version
python3 --version
uv --version
~~~

## Vérification BMAD

~~~bash
test -d _bmad && echo "BMAD directory: OK" || echo "BMAD directory: MISSING"
test -d _bmad-output && echo "BMAD output: OK" || echo "BMAD output: MISSING"
find _bmad -type f | sort | head -100
~~~

Vérifier que les skills installées correspondent à la version choisie. Ne pas conclure à partir du seul code de sortie de l'installateur.

## Vérification Matt Pocock

~~~bash
find .agents/skills .claude/skills -type f 2>/dev/null | sort | rg 'matt|to-spec|to-tickets|grill|domain|diagnos|code-review|tdd'
~~~

Vérifier en particulier les dépendances de grill-with-docs : grilling et domain-modeling.

## Vérification Superpowers

Vérifier la présence ou l'activation de :

~~~text
using-superpowers
brainstorming
writing-plans
using-git-worktrees
test-driven-development
systematic-debugging
verification-before-completion
finishing-a-development-branch
~~~

Les skills de sous-agents ne doivent pas être activées dans la chaîne externe GLM/Claude si elles provoquent une double orchestration.

## Test de routage sans modification

Soumettre au LLM cette demande fictive :

~~~text
Je veux ajouter une validation sur un formulaire existant. Ne modifie aucun fichier. Exécute le preflight, classe la demande et indique les skills qui seraient utilisés.
~~~

Résultat attendu :

~~~text
- lecture du contexte ;
- route R2 ou R3 justifiée ;
- liste des skills et dépendances ;
- aucun fichier modifié ;
- attente d'un GO si un plan est requis.
~~~

## Test de séparation des rôles

Demander à GLM :

~~~text
Implémente la tâche, écris les tests et fournis les preuves. Ne déclare pas la tâche approuvée et ne modifie pas main.
~~~

Vérifier que le retour contient :

- la branche ;
- le commit ;
- les commandes exécutées ;
- les résultats ;
- le bundle de preuves ;
- aucune auto-approbation.

## Test de revue indépendante

Donner à Claude le ticket, la spec, le diff et les résultats de tests, sans lui fournir les échanges de conception inutiles.

Vérifier que Claude produit un rapport APPROVED ou CHANGES_REQUIRED et ne modifie pas la branche.

## État final attendu

~~~text
Installation validée
Projet initialisé
Baseline connue
Routeur fonctionnel
Rôles séparés
Secrets exclus
Revue indépendante vérifiée
Git propre
~~~

