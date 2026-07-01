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

- Onglet Audit & Correction pour auditer ou corriger un projet existant.
- Onglet Creation pour creer un projet neuf sans melanger le parcours d'audit.
- Selection du chemin projet audit/correction par saisie controlee.
- Detection Git, branche, et URL GitHub quand elle existe.
- Etat des dependances: Git, Aider, Ollama, Ornith, Hermes.
- Catalogue de commandes ControlTower.
- Confirmation avant les commandes reelles qui lancent Aider.
- Chat simple pour declencher `audit`, `tests`, `git`, `diff`, `hermes` ou `aider`.
- Creation de projet depuis zero: formulaire dedie, dossier parent memorise separement, dry-run, lancement Aider/Ornith et validation des fichiers generes.

## Securite

L'API n'accepte pas de commande libre. Les actions passent par une liste autorisee dans `app.py`.

Les commandes de correction avec ticket sont affichees comme templates tant que le workspace et le ticket ne sont pas fournis explicitement.

Le mode creation appelle les scripts ControlTower, pas une commande libre du navigateur. Le dossier cible est cree dans le parent choisi, puis `Test-AiderCreation.ps1` bloque les fichiers interdits.

Le chemin du projet audit/correction et le dossier parent de creation sont stockes separement pour pouvoir piloter deux projets sans confusion.
