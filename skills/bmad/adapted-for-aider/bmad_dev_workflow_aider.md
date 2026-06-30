# BMAD Dev Workflow — Adaptation Aider / Ornith

## Objectif

Encadrer les tâches de développement local dans un dépôt Git.

## Workflow standard

### 1. Pré-check

- Lire AGENTS.md.
- Lire .agent/PROJECT_CONTEXT.md.
- Lire .agent/PROJECT_RULES.md.
- Vérifier git status.
- Identifier les fichiers nécessaires.

### 2. Plan court

Produire un plan en 3 à 7 étapes maximum.

Le plan doit préciser :
- fichiers concernés ;
- tests ;
- risques ;
- limites de périmètre.

### 3. Exécution

- Modifier uniquement les fichiers nécessaires.
- Ne pas élargir la tâche.
- Ne pas refactorer sans demande.
- Ne pas installer de dépendances sans validation.
- Ne pas toucher aux secrets.

### 4. Vérification

- Afficher le diff.
- Lancer les tests disponibles.
- Vérifier git status.
- Signaler les fichiers modifiés.

### 5. Clôture

Résumé attendu :

- Changements effectués :
- Tests lancés :
- Résultat :
- Risques restants :
- Commit recommandé :
