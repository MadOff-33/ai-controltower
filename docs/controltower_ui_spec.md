# ControlTower UI Spec

## Objectif

Fournir un cockpit local simple pour utiliser AI ControlTower sans memoriser les commandes PowerShell.

L'interface ne remplace pas Aider. Elle pilote les scripts fiables qui lancent Aider/Ollama avec le bon contexte, les bons fichiers et les bonnes validations.

## Forme

La V1 utilise une application Flask locale lancee par:

```text
C:\AI_ControlTower\apps\controltower-ui\ControlTower.cmd
```

Le lanceur Windows cree un environnement Python dedie dans `apps/controltower-ui/.venv`, installe Flask, demarre le serveur local et ouvre le navigateur sur:

```text
http://127.0.0.1:8765
```

## Ecran principal

Zones attendues:

- Selection du projet par chemin local.
- Fiche projet: chemin, branche Git, remote, GitHub URL, dernier commit, etat Git.
- Etat dependances: Git, PowerShell, Aider, Ollama, Ornith, Hermes.
- Catalogue de commandes: installation, audit, correction, Hermes, Git, tests.
- Journal/chat de pilotage: sortie lisible, commande generee, sortie brute.

## Limite navigateur

Un navigateur ne peut pas obtenir librement le chemin complet d'un dossier local via un bouton fichier. La V1 utilise donc un champ chemin controle par le serveur Flask.

Une evolution possible consiste a ajouter un dialogue natif via une petite app desktop ou Tauri, mais Flask reste le cockpit local principal.

## Commandes du catalogue

Le catalogue doit inclure:

- Installer / reparer ControlTower
- Audit dry-run
- Audit reel
- Fix dry-run
- Fix reel
- Tests complets
- Guidance Hermes
- Git status
- Git diff
- Ouvrir GitHub via lien detecte
- Ouvrir Aider manuel cadre

Les actions reelles comme `-RunAider` doivent etre separees des dry-runs et demander confirmation.

## Securite

L'API Flask ne doit pas executer de commande libre envoyee par le navigateur.

Les lancements passent par une liste autorisee dans `app.py`.

Les commandes de correction avec ticket restent des templates tant que le workspace et le ticket ne sont pas fournis.

## Outils associes

- `tools/Get-ProjectGitInfo.ps1`
- `tools/Test-ControlTowerDependencies.ps1`
- `apps/controltower-ui/app.py`
- `apps/controltower-ui/ControlTower.cmd`
- `apps/controltower-ui/requirements.txt`
- `apps/controltower-ui/templates/index.html`
- `apps/controltower-ui/static/app.js`
- `apps/controltower-ui/static/styles.css`
- `apps/controltower-ui/README.md`
- `apps/controltower-ui/state.json`
- `tools/tests/Test-ControlTowerUI.ps1`

## Critere d'acceptation

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-ControlTowerUI.ps1"
```

termine avec un code 0.
