# Release Checklist

## Installation

- [x] Hermes central memory initialisable.
- [x] Entree globale `Invoke-ControlTowerRun.ps1`.
- [x] Cockpit Flask local `apps/controltower-ui/ControlTower.cmd`.
- [x] Lanceur racine `ControlTower.cmd`.
- [x] Builder executable `tools/Build-ControlTowerLauncher.ps1`.
- [x] Suite de tests globale.
- [x] Documentation d'usage.

## Securite

- [x] Projet cible non modifie par audit.
- [x] Secrets, caches, bases de donnees et depots Git exclus du snapshot.
- [x] Rapports confines dans `reports/`.
- [x] Corrections bornees par ticket.
- [x] Fichiers hors perimetre rejetes.
- [x] Aucun commit automatique.

## Fiabilite

- [x] Chemins avec espaces testes.
- [x] Packs de contexte bornes.
- [x] Marqueurs fantomes detectes.
- [x] Hermes apprend depuis les runs.
- [x] Categories Hermes ouvertes.
- [x] GitHub remote detecte dans l'interface.
- [x] Jobs UI asynchrones disponibles.
- [x] Recette finale automatisable.
- [x] Resume humain genere par run.

## Commandes finales

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Install-ControlTower.ps1"
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Invoke-ControlTowerTestSuite.ps1"
```
