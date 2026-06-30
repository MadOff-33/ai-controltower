# AI Control Tower

Centre local de fiabilisation pour developpement assiste par IA avec Aider, Ollama et `ornith:9b`.

## Commandes principales

Lancer le cockpit Flask local:

```cmd
C:\AI_ControlTower\apps\controltower-ui\ControlTower.cmd
```

Installer ou reparer l'environnement:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Install-ControlTower.ps1"
```

Lancer un audit fiable:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "C:\chemin avec espaces\Projet" -ValidateAfterDryRun
```

Lancer toute la verification:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Invoke-ControlTowerTestSuite.ps1"
```

## Architecture

- `tools/`: scripts d'audit, correction, validation, orchestration et Hermes.
- `apps/controltower-ui/`: cockpit Flask local avec lanceur Windows.
- `docs/`: specifications, manuel, architecture et cloture.
- `prompts/`: prompts bornes pour audits.
- `templates/`: profils, tickets et schemas.
- `hermes_memory/`: memoire centrale d'experience.
- `policies/`: regles de securite et Git.
- `hermes_lab/`: zone temporaire de tests, nettoyee par les suites.

## Regle principale

ControlTower ne modifie pas le projet cible pendant un audit, ne commit pas automatiquement, ne pousse rien sans demande explicite et rejette les sorties hors perimetre.
