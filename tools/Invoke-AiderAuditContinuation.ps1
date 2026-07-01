param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$PreviousLotName = "",
  [string]$LotName = "lot2_continuation",
  [string]$PromptPath = "C:\AI_ControlTower\prompts\audit\lot2_architecture.md",
  [int]$MaxChars = 45000,
  [string]$Model = "ollama_chat/ornith:9b",
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Quote-Arg {
  param([string]$Value)
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-PipelineStep {
  param([string]$Name, [scriptblock]$Command)
  Write-Host ""
  Write-Host ("=== " + $Name + " ===")
  $global:LASTEXITCODE = 0
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw ("Etape echouee: " + $Name + " (exit " + $LASTEXITCODE + ")")
  }
}

function Get-PreviousManifest {
  param([string]$Workspace, [string]$Lot)
  $contextDir = Join-Path $Workspace "context_packs"
  if (-not (Test-Path -LiteralPath $contextDir)) { throw "Aucun dossier context_packs dans: $Workspace" }
  if (-not [string]::IsNullOrWhiteSpace($Lot)) {
    $named = Join-Path $contextDir (($Lot -replace '[^a-zA-Z0-9_.-]', '_').Trim("_") + "_manifest.json")
    if (Test-Path -LiteralPath $named) { return $named }
    throw "Manifeste precedent introuvable: $named"
  }
  $manifest = Get-ChildItem -LiteralPath $contextDir -File -Filter "*_manifest.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $manifest) { throw "Aucun manifeste de contexte trouve dans: $contextDir" }
  return $manifest.FullName
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
if (-not (Test-Path -LiteralPath $PromptPath)) { throw "Prompt introuvable: $PromptPath" }

$root = "C:\AI_ControlTower"
$contextScript = Join-Path $root "tools\New-ContextPack.ps1"
$startScript = Join-Path $root "tools\Start-AiderAudit.ps1"
$validateScript = Join-Path $root "tools\Test-AiderOutput.ps1"
foreach ($scriptPath in @($contextScript, $startScript, $validateScript)) {
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Script introuvable: $scriptPath" }
}

$previousManifestPath = Get-PreviousManifest -Workspace $workspace -Lot $PreviousLotName
$previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json
$omittedPaths = @($previousManifest.omitted | ForEach-Object { $_.path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($omittedPaths.Count -eq 0) {
  throw "Aucun fichier omis a reprendre. L'audit precedent est deja complet pour ce manifeste."
}

$safeLot = ($LotName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeLot)) { throw "LotName invalide." }

Write-Host "=== Aider audit continuation ==="
Write-Host ("Workspace:      " + $workspace)
Write-Host ("Previous lot:   " + $previousManifest.lot)
Write-Host ("Continuation:   " + $safeLot)
Write-Host ("Files to cover: " + $omittedPaths.Count)
Write-Host ("Mode:           " + $(if ($RunAider) { "RunAider" } else { "DryRun" }))

Invoke-PipelineStep -Name "Create continuation context pack" -Command {
  & $contextScript -WorkspacePath $workspace -LotName $safeLot -PromptPath $PromptPath -MaxChars $MaxChars -IncludePaths $omittedPaths -PreviousManifestPath $previousManifestPath
}

$contextPack = Join-Path $workspace ("context_packs\" + $safeLot + "_pack.md")
$reportPath = Join-Path $workspace ("reports\" + $safeLot + "_report.md")

$startArgs = @{
  WorkspacePath = $workspace
  LotName = $safeLot
  ContextPackPath = $contextPack
  Model = $Model
}
if (-not $RunAider) { $startArgs["DryRun"] = $true }

Invoke-PipelineStep -Name "Start Aider continuation" -Command {
  & $startScript @startArgs
}

$validationStatus = "skipped"
if ($RunAider -or $ValidateAfterDryRun) {
  Invoke-PipelineStep -Name "Validate continuation output" -Command {
    $validateArgs = @{
      WorkspacePath = $workspace
      ReportPath = $reportPath
      ContextPackPath = $contextPack
    }
    if ((-not $RunAider) -and $ValidateAfterDryRun) { $validateArgs["AllowDraftReport"] = $true }
    & $validateScript @validateArgs
  }
  $validationStatus = $(if ($RunAider) { "passed" } else { "structure-passed" })
}

$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
$result = [ordered]@{
  completed_at = (Get-Date).ToString("o")
  workspace_path = $workspace
  previous_manifest = $previousManifestPath
  lot = $safeLot
  context_pack = $contextPack
  report_path = $reportPath
  files_requested = $omittedPaths.Count
  model = $Model
  mode = $(if ($RunAider) { "RunAider" } else { "DryRun" })
  validation = $validationStatus
}
Write-Utf8NoBom -Path (Join-Path $validationDir ($safeLot + "_pipeline_result.json")) -Content ($result | ConvertTo-Json -Depth 6)

Write-Host ""
Write-Host "=== Continuation summary ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Pack:      " + $contextPack)
Write-Host ("Report:    " + $reportPath)
Write-Host ("Validation:" + " " + $validationStatus)
Write-Host ""
Write-Host "Next command:"
if ($RunAider -or $ValidateAfterDryRun) {
  Write-Host "Relire le rapport de continuation ou relancer Continuer audit si la couverture reste incomplete."
} else {
  Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg $validateScript) + " -WorkspacePath " + (Quote-Arg $workspace) + " -ReportPath " + (Quote-Arg $reportPath) + " -ContextPackPath " + (Quote-Arg $contextPack))
}
