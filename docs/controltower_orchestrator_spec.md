# ControlTower Orchestrator Spec

## Objectif

`Invoke-ControlTowerRun.ps1` devient l'entree principale pour piloter les briques fiables existantes:

- audit fiable V1.1;
- correction bornee V2;
- journal global de run;
- mode sec par defaut.

L'orchestrateur ne remplace pas les scripts specialises. Il les compose.

## Modes

### Audit

Le mode `Audit` appelle `Invoke-AiderAuditPipeline.ps1`.

Resultat attendu:

- workspace d'audit cree;
- inventaire et pack generes;
- rapport cree dans `reports/`;
- validation possible en dry-run;
- journal global dans `logs/controltower_runs/`.

### Fix

Le mode `Fix` appelle `Invoke-AiderFixPipeline.ps1`.

Contraintes:

- `-WorkspacePath` est obligatoire;
- `-TicketPath` est obligatoire;
- la correction reste dans `source_snapshot/`;
- lancement reel seulement avec `-RunAider`.

### AuditThenFix

Le mode `AuditThenFix` cree d'abord un workspace d'audit, puis execute un ticket de correction fourni.

Contraintes:

- le ticket doit appartenir au workspace obtenu ou etre fourni apres creation par une etape humaine;
- en V2.1, le mode est reserve aux tickets deja existants dans un workspace donne. L'enchainement automatique rapport -> ticket reste une V3.

## Securite

- Le mode par defaut est dry-run.
- Aucun commit automatique.
- Aucun push.
- Le projet cible n'est jamais modifie.
- Le journal global est append-only au niveau fichier: un run cree un nouveau JSON.

## Critere d'acceptation

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-ControlTowerOrchestrator.ps1"
```

termine avec un code 0.
