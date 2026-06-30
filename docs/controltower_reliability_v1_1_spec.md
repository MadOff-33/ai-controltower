# ControlTower Reliability V1.1 Spec

## Objectif

V1.1 durcit la couche `AI_ControlTower` autour d'Aider/Ollama sans modifier Ornith. Ornith reste le modele Ollama appele via `ollama_chat/ornith:9b`; Aider reste le moteur d'edition. ControlTower devient l'orchestrateur fiable qui prepare le contexte, lance Aider de facon cadree et verifie les sorties.

## Portee

V1.1 couvre le mode audit. Le mode correction fiable sera une V2 separee.

## Ajouts V1.1

- Ajouter un orchestrateur unique `tools/Invoke-AiderAuditPipeline.ps1`.
- Ajouter un test PowerShell reproductible `tools/tests/Test-AiderReliabilityLayer.ps1`.
- Verifier automatiquement:
  - compatibilite syntaxe PowerShell des scripts principaux;
  - absence de BOM UTF-8 sur les livrables;
  - support des chemins avec espaces;
  - exclusion des secrets, depots Git, caches et bases de donnees;
  - creation inventaire, pack contexte, rapport et baseline;
  - echec du validateur si un fichier hors perimetre est cree;
  - echec du validateur si le rapport cible n'est pas sous `reports/`;
  - echec du validateur sur marqueur de fichier fantome absent du contexte.

## Orchestrateur

`Invoke-AiderAuditPipeline.ps1` enchaine:

1. `New-AuditWorkspace.ps1`
2. `New-ProjectInventory.ps1`
3. `New-ContextPack.ps1`
4. `Start-AiderAudit.ps1`
5. `Test-AiderOutput.ps1` si un rapport existe et si Aider a ete lance ou si `-ValidateAfterDryRun` est fourni.

Par defaut, l'orchestrateur est prudent:

- il lance Aider en mode sec;
- il affiche chaque etape;
- il ecrit un resume JSON dans `validation/pipeline_result.json`;
- il affiche la prochaine commande a lancer.

Pour lancer Aider reellement, l'utilisateur doit passer `-RunAider`.

## Regles de fiabilite

- Les scripts doivent rester compatibles PowerShell 5.1.
- Les fichiers generes doivent etre en UTF-8 sans BOM.
- Le projet cible ne doit jamais etre modifie.
- Les rapports doivent rester sous `reports/`.
- Toute modification hors `reports/` ou `validation/` apres baseline doit faire echouer la validation.
- Les packs de contexte doivent rester bornes par `-MaxChars`.
- Les chemins affiches dans les commandes doivent etre entre guillemets.

## Critere d'acceptation

La V1.1 est acceptee si:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-AiderReliabilityLayer.ps1"
```

termine avec un code 0 et nettoie ses dossiers temporaires.
