# ControlTower Architecture

## Role

AI ControlTower fiabilise le developpement local assiste par IA autour d'Aider, Ollama et du modele `ornith:9b`.

ControlTower n'est pas un modele. C'est une couche d'orchestration, de contexte, de validation et de memoire.

## Couches

```text
Utilisateur
  -> Invoke-ControlTowerRun.ps1
    -> Audit pipeline
    -> Fix pipeline
    -> Validators
    -> Hermes central memory
      -> Aider
        -> Ollama / ornith:9b
```

## Principes

- Le projet cible n'est jamais modifie pendant un audit.
- Les corrections se font dans `source_snapshot/`.
- Aider ne recoit pas tout le projet, mais un contexte borne.
- Ornith/Aider ne corrige pas un projet, il corrige un ticket.
- Les validations priment sur le texte produit par le modele.
- Hermes apprend de l'experience, sans enfermer les categories.

## Entrees principales

- `tools/Install-ControlTower.ps1`: installation locale et Hermes.
- `tools/Invoke-ControlTowerRun.ps1`: entree globale.
- `tools/tests/Invoke-ControlTowerTestSuite.ps1`: verification complete.

## Pipelines

Audit:

```text
New-AuditWorkspace
  -> New-ProjectInventory
  -> New-ContextPack
  -> Start-AiderAudit
  -> Test-AiderOutput
```

Fix:

```text
New-AiderFixTicket
  -> New-FixContextPack
  -> Start-AiderFix
  -> Test-AiderFix
```

Hermes:

```text
Initialize-HermesMemory
  -> Add-HermesMemoryEntry
  -> Update-HermesFromRun
  -> Get-HermesGuidance
```

## Limites assumees

- Pas d'application automatique du patch au projet cible.
- Pas de commit automatique.
- Pas de push automatique hors demande explicite.
- `AuditThenFix` automatique reste bloque tant qu'un ticket explicite n'est pas genere et valide.
