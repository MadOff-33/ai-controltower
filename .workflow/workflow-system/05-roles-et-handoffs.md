# 05 — Rôles et handoffs

## Handoff Codex → GLM

~~~~markdown
# GLM Implementation Handoff

## Contexte
[Projet, story, commit de base]

## Mission
[Une seule mission vérifiable]

## Contraintes critiques
- [Règle 1]
- [Règle 2]

## Fichiers autorisés
- [Chemins]

## Tests obligatoires
- [Test ou comportement]

## Commandes
~~~bash
[commande de test ciblée]
[commande de test complète]
~~~

## Livrables attendus
- code ;
- tests ;
- rapport de tests ;
- evidence bundle ;
- commit SHA.

## Interdictions
- pas de merge ;
- pas de push vers main ;
- pas d'auto-approbation ;
- pas de modification hors périmètre.
~~~~

## Handoff Codex → Claude

~~~~markdown
# Independent Review Handoff

## Objet
[Story ou ticket]

## Référence
- Base SHA: [SHA]
- Head SHA: [SHA]
- Spec: [chemin]

## À examiner
- conformité à la spec ;
- architecture ;
- sécurité ;
- tests ;
- régressions ;
- secrets ;
- qualité et maintenabilité.

## Règle
Ne pas modifier la branche. Produire uniquement un rapport de revue.

## Sortie
APPROVED ou CHANGES_REQUIRED, avec findings structurés.
~~~~

## Evidence bundle GLM

Un bundle doit contenir :

~~~text
evidence/
├── metadata.yaml
├── diff.patch
├── tests.txt
├── build.txt
├── security-scan.txt
└── summary.md
~~~

metadata.yaml doit préciser le modèle, le provider, l'identité de l'agent, le commit de base, le commit final et les commandes exécutées.
