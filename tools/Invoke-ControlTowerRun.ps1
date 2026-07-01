param(
  [ValidateSet("Audit", "Fix", "AuditThenFix")]
  [string]$Mode = "Audit",

  [string]$ProjectPath = "",
  [string]$WorkspaceRoot = "C:\AI_ControlTower\audits",
  [string]$WorkspacePath = "",
  [string]$TicketPath = "",
  [string]$AuditName = "",
  [string]$LotName = "lot1_config",
  [string]$PromptPath = "C:\AI_ControlTower\prompts\audit\lot1_config.md",
  [string]$ProfilePath = "C:\AI_ControlTower\templates\audit_profiles\python-basic.yaml",
  [string]$Model = "ollama_chat/ornith:9b",
  [string]$LogRoot = "C:\AI_ControlTower\logs",
  [string]$HermesMemoryRoot = "C:\AI_ControlTower\hermes_memory",
  [int]$MaxChars = 0,
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun,
  [switch]$SkipHermes
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

function Get-NewestDirectory {
  param([string]$Path)
  $dir = Get-ChildItem -LiteralPath $Path -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $dir) { throw "Aucun workspace trouve dans: $Path" }
  return $dir.FullName
}

function Get-PipelineStatus {
  param([string]$Workspace, [string]$ResultFileName)
  $resultPath = Join-Path $Workspace ("validation\" + $ResultFileName)
  if (-not (Test-Path -LiteralPath $resultPath)) { return "passed" }
  $pipelineResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
  $validation = [string]$pipelineResult.validation
  if ([string]::IsNullOrWhiteSpace($validation) -or $validation -eq "skipped") { return "prepared" }
  return $validation
}

function New-RunLog {
  param(
    [string]$Mode,
    [string]$Status,
    [hashtable]$Data
  )
  $runLogDir = Join-Path $LogRoot "controltower_runs"
  New-Item -ItemType Directory -Path $runLogDir -Force | Out-Null
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  $path = Join-Path $runLogDir ($stamp + "_" + $Mode.ToLowerInvariant() + ".json")
  $payload = [ordered]@{
    created_at = (Get-Date).ToString("o")
    mode = $Mode
    status = $Status
    data = $Data
  }
  Write-Utf8NoBom -Path $path -Content ($payload | ConvertTo-Json -Depth 8)
  return $path
}

function New-RunSummary {
  param(
    [string]$Mode,
    [string]$Status,
    [hashtable]$Data,
    [string]$RunLogPath
  )
  $runLogDir = Split-Path -Parent $RunLogPath
  $summaryPath = [System.IO.Path]::ChangeExtension($RunLogPath, ".summary.md")
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# ControlTower run summary") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Mode: $Mode") | Out-Null
  $lines.Add("- Status: $Status") | Out-Null
  $lines.Add("- Run log: $RunLogPath") | Out-Null
  $lines.Add("- Created: $((Get-Date).ToString("o"))") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("## Artefacts") | Out-Null
  foreach ($key in $Data.Keys | Sort-Object) {
    $lines.Add("- ${key}: $($Data[$key])") | Out-Null
  }
  $lines.Add("") | Out-Null
  $lines.Add("## Next action") | Out-Null
  if ($Status -eq "structure-passed") {
    $lines.Add("Lancer un audit reel avec `-RunAider` pour produire un rapport exploitable.") | Out-Null
  } elseif ($Status -eq "passed") {
    $lines.Add("Relire les rapports et creer un ticket de correction borne si necessaire.") | Out-Null
  } elseif ($Status -eq "prepared") {
    $lines.Add("Relire les artefacts de preparation puis lancer l'action reelle si le perimetre est correct.") | Out-Null
  } else {
    $lines.Add("Corriger la cause du blocage puis relancer le run.") | Out-Null
  }
  Write-Utf8NoBom -Path $summaryPath -Content ($lines -join [Environment]::NewLine)
  return $summaryPath
}

$root = "C:\AI_ControlTower"
$auditPipeline = Join-Path $root "tools\Invoke-AiderAuditPipeline.ps1"
$fixPipeline = Join-Path $root "tools\Invoke-AiderFixPipeline.ps1"
$initHermes = Join-Path $root "tools\Initialize-HermesMemory.ps1"
$updateHermes = Join-Path $root "tools\Update-HermesFromRun.ps1"
$guidanceHermes = Join-Path $root "tools\Get-HermesGuidance.ps1"
foreach ($scriptPath in @($auditPipeline, $fixPipeline)) {
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Script introuvable: $scriptPath" }
}

Write-Host "=== ControlTower run ==="
Write-Host ("Mode:  " + $Mode)
Write-Host ("Model: " + $Model)
Write-Host ("Aider: " + $(if ($RunAider) { "real run" } else { "dry-run" }))
Write-Host ("Hermes:" + " " + $(if ($SkipHermes) { "skipped" } else { $HermesMemoryRoot }))

$status = "started"
$result = @{}
$logPath = ""

try {
  if ($Mode -eq "Audit") {
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { throw "ProjectPath est obligatoire en mode Audit." }
    $auditArgs = @{
      ProjectPath = $ProjectPath
      WorkspaceRoot = $WorkspaceRoot
      AuditName = $AuditName
      ProfilePath = $ProfilePath
      LotName = $LotName
      PromptPath = $PromptPath
      Model = $Model
    }
    if ($MaxChars -gt 0) { $auditArgs["MaxChars"] = $MaxChars }
    if ($RunAider) { $auditArgs["RunAider"] = $true }
    if ($ValidateAfterDryRun) { $auditArgs["ValidateAfterDryRun"] = $true }
    & $auditPipeline @auditArgs
    $workspace = Get-NewestDirectory -Path $WorkspaceRoot
    $result = @{
      project_path = $ProjectPath
      workspace_path = $workspace
      pipeline = "audit"
    }
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName "pipeline_result.json"
  } elseif ($Mode -eq "Fix") {
    if ([string]::IsNullOrWhiteSpace($WorkspacePath)) { throw "WorkspacePath est obligatoire en mode Fix." }
    if ([string]::IsNullOrWhiteSpace($TicketPath)) { throw "TicketPath est obligatoire en mode Fix." }
    $workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
    $ticket = (Resolve-Path -LiteralPath $TicketPath).ProviderPath
    $fixArgs = @{
      WorkspacePath = $workspace
      TicketPath = $ticket
      Model = $Model
    }
    if ($MaxChars -gt 0) { $fixArgs["MaxChars"] = $MaxChars }
    if ($RunAider) { $fixArgs["RunAider"] = $true }
    if ($ValidateAfterDryRun) { $fixArgs["ValidateAfterDryRun"] = $true }
    & $fixPipeline @fixArgs
    $result = @{
      workspace_path = $workspace
      ticket_path = $ticket
      pipeline = "fix"
    }
    $ticketId = [System.IO.Path]::GetFileNameWithoutExtension($ticket)
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName ($ticketId + "_pipeline_result.json")
  } else {
    throw "AuditThenFix automatique est reserve a une version ulterieure. Utiliser Audit puis Fix avec un ticket explicite."
  }

  $logPath = New-RunLog -Mode $Mode -Status $status -Data $result
} catch {
  $status = "failed"
  $result = @{
    error = $_.Exception.Message
    project_path = $ProjectPath
    workspace_path = $WorkspacePath
    ticket_path = $TicketPath
  }
  $logPath = New-RunLog -Mode $Mode -Status $status -Data $result
  Write-Host ("ControlTower run failed: " + $_.Exception.Message)
  Write-Host ("Run log: " + $logPath)
  exit 1
}

if (-not $SkipHermes) {
  try {
    if (Test-Path -LiteralPath $initHermes) {
      & $initHermes -MemoryRoot $HermesMemoryRoot | Out-Null
    }
    if ((Test-Path -LiteralPath $updateHermes) -and (Test-Path -LiteralPath $logPath)) {
      & $updateHermes -MemoryRoot $HermesMemoryRoot -RunResultPath $logPath | Out-Null
    }
    if (Test-Path -LiteralPath $guidanceHermes) {
      & $guidanceHermes -MemoryRoot $HermesMemoryRoot | Out-Null
    }
  } catch {
    Write-Host ("Hermes update warning: " + $_.Exception.Message)
  }
}

$summaryPath = New-RunSummary -Mode $Mode -Status $status -Data $result -RunLogPath $logPath

Write-Host ""
Write-Host "=== ControlTower summary ==="
Write-Host ("Status:  " + $status)
Write-Host ("Run log: " + $logPath)
Write-Host ("Summary: " + $summaryPath)
if (-not $SkipHermes) {
  Write-Host ("Hermes:  " + (Join-Path $HermesMemoryRoot "central\guidance_cache.md"))
}
Write-Host ""
Write-Host "Next command:"
if ($Mode -eq "Audit") {
  Write-Host "Creer un ticket avec New-AiderFixTicket.ps1 ou lancer un autre lot d'audit."
} elseif ($Mode -eq "Fix") {
  Write-Host "Relire validation/*_result.json puis appliquer manuellement le patch si accepte."
}
