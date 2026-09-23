# 05 — Adaptateurs d'agents

Le workflow conserve un même contrat, puis adapte uniquement l'instruction de démarrage à l'agent. Les permissions restent les mêmes : Codex coordonne, GLM implémente, Claude révise indépendamment.

Charger l'adaptateur correspondant avant le premier message de projet. Ne pas fournir tous les adaptateurs au modèle si un seul agent est utilisé.

