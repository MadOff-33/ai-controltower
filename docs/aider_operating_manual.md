# Aider Reliability Layer - Operating Manual

## Principe

Ne lancez pas Aider directement dans le projet cible pour un audit. Lancez-le dans un workspace ControlTower cree a partir d'un snapshot filtre. Aider ne voit qu'un pack de contexte read-only et ne peut ecrire que dans un rapport sous `reports/`.

## Demarrage rapide

Interface Flask locale:

```cmd
C:\AI_ControlTower\apps\controltower-ui\ControlTower.cmd
```

Entree globale recommandee:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "C:\chemin avec espaces\Projet" -ValidateAfterDryRun
```

Commande recommandee V1.1:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-AiderAuditPipeline.ps1" -ProjectPath "C:\chemin avec espaces\Projet" -ValidateAfterDryRun
```

Cette commande cree le workspace, le snapshot, l'inventaire, le pack contexte, le rapport, puis valide la sortie en mode sec. Pour lancer Aider reellement, ajoutez `-RunAider`.

Commande pas-a-pas:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-AuditWorkspace.ps1" -ProjectPath "C:\chemin avec espaces\Projet"
```

Suivez ensuite la commande `Next command:` affichee par chaque script.

## Flux complet

1. Creer le workspace et le snapshot:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-AuditWorkspace.ps1" -ProjectPath "C:\chemin avec espaces\Projet"
```

2. Generer l'inventaire:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-ProjectInventory.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet"
```

3. Generer un pack:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-ContextPack.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -LotName "lot1_config" -PromptPath "C:\AI_ControlTower\prompts\audit\lot1_config.md"
```

4. Verifier la commande Aider sans lancer:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Start-AiderAudit.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -LotName "lot1_config" -ContextPackPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\context_packs\lot1_config_pack.md" -DryRun
```

5. Lancer Aider:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Start-AiderAudit.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -LotName "lot1_config" -ContextPackPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\context_packs\lot1_config_pack.md"
```

6. Valider la sortie:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Test-AiderOutput.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -ReportPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\reports\lot1_config_report.md" -ContextPackPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\context_packs\lot1_config_pack.md"
```

## Lots fournis

- `lot1_config`: configuration, dependances, environnement, secrets probables.
- `lot2_architecture`: organisation, points d'entree, risques d'architecture.

## Limite de contexte

Le profil Python limite par defaut les packs a `45000` caracteres. Pour un modele local avec une fenetre pratique autour de 16k tokens, reduisez si necessaire:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-ContextPack.ps1" -WorkspacePath "..." -LotName "lot1_config" -PromptPath "C:\AI_ControlTower\prompts\audit\lot1_config.md" -MaxChars 30000
```

## Regles de securite

- Le projet cible n'est jamais modifie.
- Les secrets, environnements virtuels, caches, bases de donnees, executables et depots Git ne sont pas copies.
- Les rapports doivent rester dans `reports/`.
- Aucun commit automatique n'est effectue.
- Si la validation echoue, corrigez le rapport ou supprimez les fichiers non autorises dans le workspace d'audit, puis relancez le validateur.

## Test de fiabilite local

Apres modification de la couche ControlTower, lancez:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-AiderReliabilityLayer.ps1"
```

Ce test cree un projet temporaire avec espaces dans le chemin, verifie les exclusions sensibles, execute le pipeline en mode sec, puis controle que le validateur bloque les sorties non autorisees et les marqueurs fantomes.

## Mode correction fiable V2

Le mode correction part d'un workspace d'audit existant. Les changements sont faits dans `source_snapshot/`, jamais dans le projet cible.

1. Creer un ticket:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-AiderFixTicket.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -TicketId "fix_exemple" -Title "Corriger add" -Goal "Corriger la fonction add." -EditableFiles @("pkg/core.py") -ReadonlyFiles @("README.md") -VerificationCommands @("python -c ""from pkg.core import add; assert add(2, 3) == 5""") -AcceptanceCriteria @("add retourne la somme.")
```

2. Lancer le pipeline de correction en mode sec:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-AiderFixPipeline.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -TicketPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\fix_tickets\fix_exemple.yaml" -ValidateAfterDryRun
```

3. Lancer Aider reellement:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-AiderFixPipeline.ps1" -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -TicketPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\fix_tickets\fix_exemple.yaml" -RunAider
```

Validation V2:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-AiderFixReliability.ps1"
```

Le validateur de correction echoue si Aider modifie, cree ou supprime un fichier absent de `editable_files`.

## Orchestrateur global V2.1

`Invoke-ControlTowerRun.ps1` est l'entree principale. Il compose les pipelines audit et fix, puis ecrit un journal JSON dans `logs/controltower_runs/`.

Audit:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "C:\chemin avec espaces\Projet" -ValidateAfterDryRun
```

Correction:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Fix -WorkspacePath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet" -TicketPath "C:\AI_ControlTower\audits\YYYYMMDD-HHMMSS_Projet\fix_tickets\fix_exemple.yaml"
```

Pour lancer Aider reellement, ajoutez `-RunAider`. Le mode `AuditThenFix` automatique est volontairement bloque en V2.1: il faudra d'abord generer ou valider un ticket explicite.

Validation de l'orchestrateur:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-ControlTowerOrchestrator.ps1"
```

## Hermes central memory V3

Hermes est la memoire centrale d'experience de ControlTower. Elle stocke les apprentissages transversaux: echecs, succes, hypotheses, contre-exemples, regles emergentes, limites d'outils et comportements observes du modele.

Installer ou reparer Hermes:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Initialize-HermesMemory.ps1"
```

Ajouter une experience manuelle:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Add-HermesMemoryEntry.ps1" -Kind "experience" -Category "workflow" -Summary "Les tickets courts produisent des corrections plus ciblees." -Source "manual" -Confidence "medium"
```

Generer la guidance courte:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Get-HermesGuidance.ps1"
```

Validation Hermes:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-HermesMemory.ps1"
```

Par defaut, `Invoke-ControlTowerRun.ps1` met Hermes a jour apres chaque run. Ajoutez `-SkipHermes` pour desactiver cet apprentissage.
