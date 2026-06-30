# Aider Fix Reliability V2 Spec

## Objectif

La V2 ajoute un mode correction fiable autour d'Aider/Ollama. Ornith reste le modele local appele par Aider; ControlTower prepare une mission bornee, lance Aider uniquement avec les fichiers autorises, puis valide le diff.

## Principe central

Aider ne corrige jamais "le projet". Il corrige un ticket atomique.

Un ticket definit:

- un objectif unique;
- les fichiers editables autorises;
- les fichiers read-only utiles;
- les tests ou commandes de verification;
- les criteres d'acceptation;
- les interdictions.

## Workflow

```text
New-AiderFixTicket.ps1
  -> New-FixContextPack.ps1
  -> Start-AiderFix.ps1
  -> Test-AiderFix.ps1
  -> Invoke-AiderFixPipeline.ps1
```

## Workspace de correction

La correction s'appuie sur le workspace d'audit existant:

```text
audit-workspace/
  source_snapshot/
  fix_tickets/
  fix_context_packs/
  fix_runs/
  validation/
```

Le projet cible reste intouchable. Les corrections se font dans `source_snapshot/`. L'application au vrai projet sera une etape ulterieure.

## Scripts

### New-AiderFixTicket.ps1

Produit un ticket YAML simple sous `fix_tickets/`.

Contraintes:

- tous les fichiers editables doivent exister dans `source_snapshot/`;
- les chemins sont relatifs au snapshot et normalises avec `/`;
- aucun chemin absolu n'est accepte;
- les fichiers exclus du snapshot ne peuvent pas etre references.

### New-FixContextPack.ps1

Produit un pack markdown sous `fix_context_packs/`.

Contraintes:

- inclut le ticket;
- inclut les fichiers editables et read-only;
- respecte `-MaxChars`;
- signale les omissions dans un manifeste JSON.

### Start-AiderFix.ps1

Prepare et lance Aider.

Contraintes:

- le dossier courant Aider est `source_snapshot/`;
- seuls les fichiers editables du ticket sont passes comme arguments editables;
- les fichiers read-only et le pack contexte sont charges via message `/read-only`;
- auto-commit interdit;
- `-DryRun` par defaut recommande pour verification.

### Test-AiderFix.ps1

Valide le resultat.

Contraintes:

- echoue si un fichier hors liste editable est cree, modifie ou supprime dans `source_snapshot/`;
- echoue si un marqueur fantome apparait dans les fichiers modifies sans etre present dans le contexte;
- lance les commandes de verification du ticket si elles existent;
- ecrit `validation/fix_<ticket>_result.json`.

### Invoke-AiderFixPipeline.ps1

Orchestre pack, lancement et validation.

Par defaut:

- mode sec;
- validation optionnelle apres dry-run;
- lancement reel seulement avec `-RunAider`.

## Critere d'acceptation

La V2 est acceptee si:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-AiderFixReliability.ps1"
```

termine avec un code 0.
