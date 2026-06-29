# AI Control Tower

Centre de contrôle local pour le développement assisté par IA.

## Rôle

- Centraliser les règles globales.
- Centraliser les skills BMAD et Superpowers.
- Centraliser les scripts de test, audit, sécurité et Git.
- Fournir les launchers Aider/Ollama.
- Préparer les projets locaux sans dupliquer toute la méthode.

## Architecture

- skills/ : méthodes et workflows.
- tools/ : scripts exécutables contrôlés.
- launchers/ : scripts de démarrage.
- policies/ : règles de sécurité et d’usage.
- logs/ : journaux locaux.
- hermes_lab/ : zone expérimentale uniquement.

## Règle principale

Aucun outil IA ne pousse en production, ne modifie les secrets, ni n’exécute d’action serveur sans validation humaine explicite.
