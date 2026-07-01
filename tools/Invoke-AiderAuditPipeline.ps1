param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,

  [string]$WorkspaceRoot = "C:\AI_ControlTower\audits",
  [string]$AuditName = "",
  [string]$ProfilePath = "C:\AI_ControlTower\templates\audit_profiles\python-basic.yaml",
  [string]$LotName = "lot1_config",
  [string]$PromptPath = "C:\AI_ControlTower\prompts\audit\lot1_config.md",
  [int]$MaxChars = 0,
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

function Get-NewestDirectory {
  param([string]$Path)
  $dir = Get-ChildItem -LiteralPath $Path -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $dir) { throw "Aucun workspace trouve dans: $Path" }
  return $dir.FullName
}

if (-not (Test-Path -LiteralPath $ProjectPath)) {
  throw "Projet introuvable: $ProjectPath"
}
if (-not (Test-Path -LiteralPath $ProfilePath)) {
  throw "Profil introuvable: $ProfilePath"
}
if (-not (Test-Path -LiteralPath $PromptPath)) {
  throw "Prompt introuvable: $PromptPath"
}
if (-not (Test-Path -LiteralPath $WorkspaceRoot)) {
  New-Item -ItemType Directory -Path $WorkspaceRoot | Out-Null
}

$root = "C:\AI_ControlTower"
$newWorkspaceScript = Join-Path $root "tools\New-AuditWorkspace.ps1"
$inventoryScript = Join-Path $root "tools\New-ProjectInventory.ps1"
$contextScript = Join-Path $root "tools\New-ContextPack.ps1"
$startScript = Join-Path $root "tools\Start-AiderAudit.ps1"
$validateScript = Join-Path $root "tools\Test-AiderOutput.ps1"

foreach ($scriptPath in @($newWorkspaceScript, $inventoryScript, $contextScript, $startScript, $validateScript)) {
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Script introuvable: $scriptPath" }
}

Write-Host "=== Aider audit pipeline ==="
Write-Host ("Project:       " + (Resolve-Path -LiteralPath $ProjectPath).ProviderPath)
Write-Host ("WorkspaceRoot: " + $WorkspaceRoot)
Write-Host ("Lot:           " + $LotName)
Write-Host ("Mode:          " + $(if ($RunAider) { "RunAider" } else { "DryRun" }))

Invoke-PipelineStep -Name "Create audit workspace" -Command {
  & $newWorkspaceScript -ProjectPath $ProjectPath -WorkspaceRoot $WorkspaceRoot -AuditName $AuditName -ProfilePath $ProfilePath
}

$workspace = Get-NewestDirectory -Path $WorkspaceRoot
$safeLot = ($LotName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeLot)) { throw "LotName invalide." }

Invoke-PipelineStep -Name "Create project inventory" -Command {
  & $inventoryScript -WorkspacePath $workspace
}

$contextArgs = @{
  WorkspacePath = $workspace
  LotName = $safeLot
  PromptPath = $PromptPath
}
if ($MaxChars -gt 0) { $contextArgs["MaxChars"] = $MaxChars }

Invoke-PipelineStep -Name "Create context pack" -Command {
  & $contextScript @contextArgs
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

Invoke-PipelineStep -Name "Start Aider audit" -Command {
  & $startScript @startArgs
}

$validationStatus = "skipped"
if ($RunAider -or $ValidateAfterDryRun) {
  Invoke-PipelineStep -Name "Validate Aider output" -Command {
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
  project_path = (Resolve-Path -LiteralPath $ProjectPath).ProviderPath
  workspace_path = $workspace
  lot = $safeLot
  context_pack = $contextPack
  report_path = $reportPath
  model = $Model
  mode = $(if ($RunAider) { "RunAider" } else { "DryRun" })
  validation = $validationStatus
}
Write-Utf8NoBom -Path (Join-Path $validationDir "pipeline_result.json") -Content ($result | ConvertTo-Json -Depth 6)

Write-Host ""
Write-Host "=== Pipeline summary ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Pack:      " + $contextPack)
Write-Host ("Report:    " + $reportPath)
Write-Host ("Validation:" + " " + $validationStatus)
Write-Host ""
Write-Host "Next command:"
if ($RunAider -or $ValidateAfterDryRun) {
  Write-Host "Relire le rapport dans reports/ ou lancer le lot suivant."
} else {
  Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg $validateScript) + " -WorkspacePath " + (Quote-Arg $workspace) + " -ReportPath " + (Quote-Arg $reportPath) + " -ContextPackPath " + (Quote-Arg $contextPack))
}
