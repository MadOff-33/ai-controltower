# ControlTower UI

Cockpit Flask local pour piloter AI ControlTower sans memoriser les commandes.

## Lancer

```cmd
C:\AI_ControlTower\apps\controltower-ui\ControlTower.cmd
```

Le lanceur cree un environnement Python local dans `apps/controltower-ui/.venv`, installe Flask, demarre le serveur local et ouvre le navigateur.

URL par defaut:

```text
http://127.0.0.1:8765
```

## Fonctions

- Selection du chemin projet par saisie controlee.
- Detection Git, branche, et URL GitHub quand elle existe.
- Etat des dependances: Git, Aider, Ollama, Ornith, Hermes.
- Catalogue de commandes ControlTower.
- Confirmation avant les commandes reelles qui lancent Aider.
- Chat simple pour declencher `audit`, `tests`, `git`, `diff`, `hermes` ou `aider`.

## Securite

L'API n'accepte pas de commande libre. Les actions passent par une liste autorisee dans `app.py`.

Les commandes de correction avec ticket sont affichees comme templates tant que le workspace et le ticket ne sont pas fournis explicitement.
