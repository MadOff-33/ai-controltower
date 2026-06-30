# Hermes Central Memory Spec

## Objectif

Hermes Central Memory est une memoire d'experience globale pour ControlTower. Elle ne remplace pas les contextes projet et ne stocke pas principalement des chemins locaux. Elle apprend ce que l'on attend d'un bon run, ce qui echoue, ce qui marche, les signaux faibles, les contre-exemples et les strategies utiles.

## Principe

La memoire centrale est ouverte. Elle ne doit pas rejeter un cas nouveau parce que sa categorie n'existe pas encore.

Elle impose seulement des champs de base:

- `id`
- `kind`
- `category`
- `summary`
- `source`
- `confidence`
- `status`
- `created_at`

Les champs additionnels sont libres:

- `context`
- `evidence`
- `lesson`
- `suggested_actions`
- `tags`
- `related_entries`
- `run_log`

## Structure

```text
hermes_memory/
  central/
    entries.jsonl
    index.json
    guidance_cache.md
    schema.json
```

## Kinds possibles

La liste suivante est indicative, pas restrictive:

- `experience`
- `failure`
- `success`
- `hypothesis`
- `counterexample`
- `preference`
- `workflow_rule`
- `validation_rule`
- `prompt_lesson`
- `model_behavior`
- `project_pattern`
- `tool_limitation`

## Scripts

### Initialize-HermesMemory.ps1

Cree la structure centrale et les fichiers de base sans ecraser les entrees existantes.

### Add-HermesMemoryEntry.ps1

Ajoute une entree JSONL ouverte. Les nouvelles categories sont acceptees.

### Update-HermesFromRun.ps1

Lit un resultat de run ControlTower ou validation et ajoute une experience pertinente:

- run passe: `success`
- run echoue: `failure`
- presence de `unauthorized_changes`: `validation_rule`
- presence de `ghost_findings`: `model_behavior`
- commandes echouees: `tool_limitation` ou `failure`

### Get-HermesGuidance.ps1

Produit un extrait court de guidance pour injection dans les prompts et packs.

## Critere d'acceptation

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Test-HermesMemory.ps1"
```

termine avec un code 0.
