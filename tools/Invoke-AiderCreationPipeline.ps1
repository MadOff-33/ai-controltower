param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectName,

  [Parameter(Mandatory = $true)]
  [string]$ParentPath,

  [string]$Brief = "",
  [string]$BriefPath = "",

  [string]$ProjectType = "python-basic",
  [string]$WorkspaceRoot = "C:\AI_ControlTower\creation_workspaces",
  [string]$PromptPath = "C:\AI_ControlTower\prompts\creation\new_project.md",
  [string]$Model = "ollama_chat/ornith:9b",
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun,
  [switch]$AllowExisting
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

$root = "C:\AI_ControlTower"
$newScript = Join-Path $root "tools\New-CreationWorkspace.ps1"
$startScript = Join-Path $root "tools\Start-AiderCreation.ps1"
$testScript = Join-Path $root "tools\Test-AiderCreation.ps1"
foreach ($scriptPath in @($newScript, $startScript, $testScript, $PromptPath)) {
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Fichier introuvable: $scriptPath" }
}

New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null

Write-Host "=== Aider creation pipeline ==="
Write-Host ("Project:       " + $ProjectName)
Write-Host ("ParentPath:    " + $ParentPath)
Write-Host ("WorkspaceRoot: " + $WorkspaceRoot)
Write-Host ("Mode:          " + $(if ($RunAider) { "RunAider" } else { "DryRun" }))

$workspaceArgs = @{
  ProjectName = $ProjectName
  ParentPath = $ParentPath
  ProjectType = $ProjectType
  WorkspaceRoot = $WorkspaceRoot
  PromptPath = $PromptPath
}
if (-not [string]::IsNullOrWhiteSpace($BriefPath)) {
  $workspaceArgs["BriefPath"] = $BriefPath
} else {
  $workspaceArgs["Brief"] = $Brief
}
if ($AllowExisting) { $workspaceArgs["AllowExisting"] = $true }

Invoke-PipelineStep -Name "Create creation workspace" -Command {
  & $newScript @workspaceArgs
}

$workspace = Get-NewestDirectory -Path $WorkspaceRoot

$startArgs = @{
  WorkspacePath = $workspace
  Model = $Model
}
if (-not $RunAider) { $startArgs["DryRun"] = $true }

Invoke-PipelineStep -Name "Start Aider creation" -Command {
  & $startScript @startArgs
}

$validationStatus = "skipped"
if ($RunAider -or $ValidateAfterDryRun) {
  Invoke-PipelineStep -Name "Validate Aider creation" -Command {
    & $testScript -WorkspacePath $workspace
  }
  $validationStatus = $(if ($RunAider) { "passed" } else { "structure-passed" })
}

$config = Get-Content -LiteralPath (Join-Path $workspace "creation.config.json") -Raw | ConvertFrom-Json
$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
$result = [ordered]@{
  completed_at = (Get-Date).ToString("o")
  project_name = $ProjectName
  project_type = $ProjectType
  workspace_path = $workspace
  target_project_path = [string]$config.target_project_path
  model = $Model
  mode = $(if ($RunAider) { "RunAider" } else { "DryRun" })
  validation = $validationStatus
}
Write-Utf8NoBom -Path (Join-Path $validationDir "pipeline_result.json") -Content ($result | ConvertTo-Json -Depth 6)

Write-Host ""
Write-Host "=== Creation pipeline summary ==="
Write-Host ("Workspace:  " + $workspace)
Write-Host ("Target:     " + [string]$config.target_project_path)
Write-Host ("Validation: " + $validationStatus)
Write-Host ""
Write-Host "Next command:"
if ($RunAider -or $ValidateAfterDryRun) {
  Write-Host "Ouvrir le dossier cible ou relire validation/creation_result.json."
} else {
  Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg $testScript) + " -WorkspacePath " + (Quote-Arg $workspace))
}
