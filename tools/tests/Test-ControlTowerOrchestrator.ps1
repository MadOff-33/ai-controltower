param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$Script = Join-Path $Root "tools\Invoke-ControlTowerRun.ps1"
$AuditScript = Join-Path $Root "tools\Invoke-AiderAuditPipeline.ps1"
$FixTicketScript = Join-Path $Root "tools\New-AiderFixTicket.ps1"
$TestRoot = Join-Path $Root "hermes_lab\orchestrator test runs"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

function Invoke-ExpectFailure {
  param([scriptblock]$Command, [string]$Name)
  $failed = $false
  $global:LASTEXITCODE = 0
  try {
    & $Command
    if ($LASTEXITCODE -ne 0) {
      $failed = $true
      $global:LASTEXITCODE = 0
    }
  } catch {
    $failed = $true
    $global:LASTEXITCODE = 0
  }
  Assert-True -Condition $failed -Message "Expected failure did not happen: $Name"
}

function Remove-TestTree {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $base = [System.IO.Path]::GetFullPath((Join-Path $Root "hermes_lab")).TrimEnd("\")
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  Assert-True -Condition $full.StartsWith($base + "\", [System.StringComparison]::OrdinalIgnoreCase) -Message "Unsafe cleanup path: $full"
  Remove-Item -LiteralPath $full -Recurse -Force
}

function Get-LatestWorkspace {
  param([string]$WorkspaceRoot)
  return (Get-ChildItem -LiteralPath $WorkspaceRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

Write-Host "=== Test ControlTower Orchestrator ==="

Assert-PathExists -Path $Script
foreach ($path in @($Script, $AuditScript, $FixTicketScript)) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

$bytes = [System.IO.File]::ReadAllBytes($Script)
$hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
Assert-True -Condition (-not $hasBom) -Message "UTF-8 BOM detected: $Script"

Remove-TestTree -Path $TestRoot
$project = Join-Path $TestRoot "Project With Spaces"
$workspaceRoot = Join-Path $TestRoot "Audit Workspaces"
$logRoot = Join-Path $TestRoot "Run Logs"
$hermesRoot = Join-Path $TestRoot "Hermes Memory"
New-Item -ItemType Directory -Path (Join-Path $project "pkg") -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $project "pkg\core.py"), "def add(a, b):`n    return a - b`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $project "README.md"), "# Fixture`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $project ".env"), "TOKEN=do-not-copy`n", $utf8)

& $Script -Mode Audit -ProjectPath $project -WorkspaceRoot $workspaceRoot -LogRoot $logRoot -HermesMemoryRoot $hermesRoot -ValidateAfterDryRun
$workspace = Get-LatestWorkspace -WorkspaceRoot $workspaceRoot
Assert-PathExists -Path (Join-Path $workspace "validation\pipeline_result.json")
Assert-PathExists -Path (Join-Path $logRoot "controltower_runs")
Assert-PathExists -Path (Join-Path $hermesRoot "central\guidance_cache.md")
$firstLog = Get-ChildItem -LiteralPath (Join-Path $logRoot "controltower_runs") -File | Select-Object -First 1
Assert-True -Condition ($null -ne $firstLog) -Message "No orchestrator log created for audit mode."
$firstRun = Get-Content -LiteralPath $firstLog.FullName -Raw | ConvertFrom-Json
Assert-True -Condition ($firstRun.status -eq "structure-passed") -Message ("Dry-run audit should be logged as structure-passed, got: " + $firstRun.status)

& $FixTicketScript `
  -WorkspacePath $workspace `
  -TicketId "fix_add" `
  -Title "Fix add implementation" `
  -Goal "Change pkg/core.py so add returns a + b." `
  -EditableFiles @("pkg/core.py") `
  -ReadonlyFiles @("README.md") `
  -VerificationCommands @("python -c ""from pkg.core import add; assert add(2, 3) == 5""") `
  -AcceptanceCriteria @("pkg/core.py uses addition for add.") | Out-Null
$ticket = Join-Path $workspace "fix_tickets\fix_add.yaml"

& $Script -Mode Fix -WorkspacePath $workspace -TicketPath $ticket -LogRoot $logRoot -HermesMemoryRoot $hermesRoot
Assert-PathExists -Path (Join-Path $workspace "validation\fix_add_pipeline_result.json")

Invoke-ExpectFailure -Name "fix without ticket" -Command {
  & $Script -Mode Fix -WorkspacePath $workspace -LogRoot $logRoot -HermesMemoryRoot $hermesRoot
}

$logs = Get-ChildItem -LiteralPath (Join-Path $logRoot "controltower_runs") -File
Assert-True -Condition ($logs.Count -ge 2) -Message "Expected at least two orchestrator logs."

Remove-TestTree -Path $TestRoot
Write-Host "All ControlTower orchestrator tests passed."
