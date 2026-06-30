# Aider Reliability Layer - Specification

## Objectif

La couche ControlTower fiabilise les audits Aider/Ollama en préparant un espace de travail isole, reproductible et verifiable. Le projet cible n'est jamais modifie directement: ControlTower cree un snapshot filtré, genere un inventaire, decoupe le contexte en lots compatibles avec une petite fenetre de contexte, lance Aider sur un seul rapport editable, puis valide les sorties.

## Problemes adresses

- Les chemins avec espaces sont geres par PowerShell avec `-LiteralPath` et des commandes affichees avec guillemets.
- Aider ne recoit pas une longue liste de fichiers projet. Il recoit un seul fichier contexte en lecture seule et un seul fichier rapport editable.
- Les packs de contexte sont bornes par une limite configurable de caracteres.
- Les fichiers sensibles et lourds ne sont jamais copies dans le snapshot.
- Les rapports sont limites au dossier `reports/`.
- La validation post-run detecte les fichiers hors autorisation, les marqueurs de fichiers fantomes et les affirmations factuelles non appuyees par le contexte.

## Architecture

Chaque audit vit dans un workspace dedie:

```text
audit-workspace/
  audit.config.json
  source_snapshot/
  inventory/
    files.csv
    files.json
    summary.md
  context_packs/
    lot1_config_pack.md
    lot2_architecture_pack.md
  prompts/
  reports/
    lot1_config_report.md
  validation/
    baseline_files.json
    last_result.json
```

Le workflow standard est:

1. `New-AuditWorkspace.ps1` cree le workspace, copie un snapshot filtre et ecrit la configuration.
2. `New-ProjectInventory.ps1` inventorie le snapshot.
3. `New-ContextPack.ps1` cree un pack de contexte borne.
4. `Start-AiderAudit.ps1` prepare et lance Aider avec un seul contexte read-only et un seul rapport editable.
5. `Test-AiderOutput.ps1` valide que seules les sorties autorisees ont change et signale les hallucinations simples.

## Exclusions de snapshot

ControlTower exclut toujours:

- repertoires: `.git`, `.hg`, `.svn`, `.venv`, `venv`, `env`, `.env`, `node_modules`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.cache`, `dist`, `build`, `target`, `.idea`, `.vscode`
- fichiers: `.env`, `.env.*`, `*.pem`, `*.key`, `*.pfx`, `*.sqlite`, `*.sqlite3`, `*.db`, `*.exe`, `*.dll`, `*.bin`, `*.zip`, `*.7z`, `*.tar`, `*.gz`, `*.pyc`, `*.pyo`
- noms contenant des indices sensibles: `secret`, `secrets`, `password`, `passwd`, `token`, `private_key`

La liste peut etre etendue via le profil YAML, mais pas reduite.

## Contrats des scripts

### New-AuditWorkspace.ps1

Entrees principales:

- `-ProjectPath`: chemin du projet cible.
- `-WorkspaceRoot`: dossier parent ou creer le workspace.
- `-AuditName`: nom optionnel de l'audit.
- `-ProfilePath`: profil YAML optionnel.

Sorties:

- cree un workspace horodate;
- copie uniquement les fichiers autorises dans `source_snapshot/`;
- ecrit `audit.config.json`;
- affiche la prochaine commande `New-ProjectInventory.ps1`.

### New-ProjectInventory.ps1

Entrees principales:

- `-WorkspacePath`: workspace d'audit.

Sorties:

- ecrit `inventory/files.csv`, `inventory/files.json`, `inventory/summary.md`;
- ecrit `validation/baseline_files.json`;
- affiche la prochaine commande `New-ContextPack.ps1`.

### New-ContextPack.ps1

Entrees principales:

- `-WorkspacePath`
- `-LotName`
- `-PromptPath`
- `-MaxChars`

Sorties:

- cree un unique fichier `context_packs/<lot>_pack.md`;
- utilise des chemins relatifs normalises avec `/`;
- inclut les fichiers jusqu'a la limite de caracteres;
- affiche la prochaine commande `Start-AiderAudit.ps1`.

### Start-AiderAudit.ps1

Entrees principales:

- `-WorkspacePath`
- `-LotName`
- `-ContextPackPath`
- `-ReportName`
- `-Model`
- `-DryRun`

Sorties:

- cree le rapport cible dans `reports/` si absent;
- affiche et, sauf `-DryRun`, lance Aider;
- passe le contexte avec `/read-only`;
- ne rend editable que le rapport dans `reports/`;
- affiche la prochaine commande `Test-AiderOutput.ps1`.

### Test-AiderOutput.ps1

Entrees principales:

- `-WorkspacePath`
- `-ReportPath`
- `-ContextPackPath`

Sorties:

- echoue si un fichier cree ou modifie n'est pas sous `reports/` ou `validation/`;
- echoue si le rapport cible n'est pas sous `reports/`;
- signale les marqueurs probables de fichiers fantomes: `main()`, `app.run()`, `sys.exit(app.exec_())`, chemins absolus du projet cible;
- signale les affirmations factuelles non appuyees lorsque le rapport contient des formulations fortes sans citation de chemin;
- ecrit `validation/last_result.json`;
- affiche la prochaine commande de correction ou le prochain lot.

## Profil YAML minimal

Le profil `python-basic.yaml` definit:

- extensions texte autorisees;
- exclusions additionnelles Python;
- limite de pack par defaut;
- marqueurs d'hallucination et de fichiers fantomes;
- lots recommandes.

Le parsing PowerShell reste volontairement simple pour rester compatible 5.1: le YAML sert de configuration lisible et seuls les tableaux simples `- item` sont consommes.

## Regles de lancement Aider

Aider est lance depuis le workspace d'audit, pas depuis le projet cible.

Commande logique:

```text
aider --model <model> reports/<report>.md --message-file prompts/<lot>_aider_message.md
```

Le fichier message contient les instructions `/read-only <context_pack>` puis la demande d'audit. Cette approche evite de passer de nombreux chemins a Aider et limite les erreurs liees aux espaces.

## Validation attendue

Un audit est valide lorsque:

- le projet cible n'a jamais ete modifie;
- le snapshot ne contient aucun fichier exclu;
- un seul rapport par lot est editable;
- le rapport est dans `reports/`;
- aucun fichier non autorise n'a ete cree ou modifie;
- les alertes factuelles sont examinees ou corrigees.

## Limites connues

La detection d'hallucinations est volontairement simple. Elle ne prouve pas qu'un rapport est vrai; elle detecte les affirmations a risque, les references absentes du contexte et les patrons connus de fichiers fantomes. La qualite finale vient de la combinaison: contexte borne, rapport unique, validation automatique, et revue humaine des alertes.
