# BMAD Core — Adaptation Aider / Ornith

## Objectif

Utiliser BMAD dans Aider comme méthode de cadrage, exécution, test et clôture, sans dépendre de Claude Code.

## Règles générales

- Toujours rattacher une tâche à un objectif clair.
- Toujours vérifier le contexte projet avant modification.
- Toujours travailler en petite unité contrôlable.
- Toujours préserver Git comme filet de sécurité.
- Toujours produire un diff lisible.
- Toujours tester ou expliquer clairement pourquoi le test n'est pas possible.
- Ne jamais toucher à la production sans GO explicite.
- Ne jamais accéder aux secrets.

## Cycle BMAD simplifié

1. Comprendre la demande.
2. Identifier le périmètre.
3. Lire les fichiers utiles.
4. Proposer un plan court.
5. Exécuter petit.
6. Vérifier diff.
7. Lancer tests.
8. Résumer.
9. Préparer commit local si validé.

## Règles de décision

Avant toute modification, répondre :

- Objectif compris :
- Fichiers probablement concernés :
- Risques :
- Tests prévus :
- Besoin de validation humaine : oui/non

## Usage dans Aider

Charger ce fichier en lecture seule :

/read-only C:\AI_ControlTower\skills\bmad\adapted-for-aider\bmad_core_aider.md
