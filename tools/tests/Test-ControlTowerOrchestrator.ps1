param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$Script = Join-Path $Root "tools\Invoke-ControlTowerRun.ps1"
$AuditScript = Join-Path $Root "tools\Invoke-AiderAuditPipeline.ps1"
$ContinueAuditScript = Join-Path $Root "tools\Invoke-AiderAuditContinuation.ps1"
$ConsolidateAuditScript = Join-Path $Root "tools\New-AuditConsolidatedReport.ps1"
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
foreach ($path in @($Script, $AuditScript, $ContinueAuditScript, $ConsolidateAuditScript, $FixTicketScript)) {
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
[System.IO.File]::WriteAllText((Join-Path $project "pkg\large.py"), ("# large`n" + ("x = 1`n" * 400)), $utf8)
[System.IO.File]::WriteAllText((Join-Path $project ".env"), "TOKEN=do-not-copy`n", $utf8)

& $Script -Mode Audit -ProjectPath $project -WorkspaceRoot $workspaceRoot -LogRoot $logRoot -HermesMemoryRoot $hermesRoot -MaxChars 1800 -ValidateAfterDryRun
$workspace = Get-LatestWorkspace -WorkspaceRoot $workspaceRoot
Assert-PathExists -Path (Join-Path $workspace "validation\pipeline_result.json")
Assert-PathExists -Path (Join-Path $logRoot "controltower_runs")
Assert-PathExists -Path (Join-Path $hermesRoot "central\guidance_cache.md")
$firstLog = Get-ChildItem -LiteralPath (Join-Path $logRoot "controltower_runs") -File | Select-Object -First 1
Assert-True -Condition ($null -ne $firstLog) -Message "No orchestrator log created for audit mode."
$firstRun = Get-Content -LiteralPath $firstLog.FullName -Raw | ConvertFrom-Json
Assert-True -Condition ($firstRun.status -eq "structure-passed") -Message ("Dry-run audit should be logged as structure-passed, got: " + $firstRun.status)
$firstManifest = Get-Content -LiteralPath (Join-Path $workspace "context_packs\lot1_config_manifest.json") -Raw | ConvertFrom-Json
Assert-True -Condition ($firstManifest.coverage.status -eq "partial") -Message "Small audit pack should be partial before continuation."

& $ContinueAuditScript -WorkspacePath $workspace -PreviousLotName "lot1_config" -LotName "lot2_continuation" -MaxChars 8000 -ValidateAfterDryRun | Out-Null
Assert-PathExists -Path (Join-Path $workspace "context_packs\lot2_continuation_pack.md")
Assert-PathExists -Path (Join-Path $workspace "reports\lot2_continuation_report.md")
$secondManifest = Get-Content -LiteralPath (Join-Path $workspace "context_packs\lot2_continuation_manifest.json") -Raw | ConvertFrom-Json
Assert-True -Condition ($secondManifest.coverage.previous_omitted_files -gt 0) -Message "Continuation manifest should remember previous omissions."
Assert-True -Condition ($secondManifest.coverage.included_files -gt 0) -Message "Continuation should include omitted files from previous lot."
Assert-True -Condition ($secondManifest.coverage.total_files -eq $firstManifest.coverage.total_files) -Message "Continuation should keep the project-level total file count."
Assert-True -Condition ($secondManifest.coverage.included_files -eq $secondManifest.coverage.total_files) -Message "Continuation should mark cumulative coverage complete when all files are covered."

& $ConsolidateAuditScript -WorkspacePath $workspace | Out-Null
$globalReport = Get-ChildItem -LiteralPath (Join-Path $workspace "reports") -File -Filter "Project_With_Spaces_audit_*_global_report.md" | Select-Object -First 1
Assert-True -Condition ($null -ne $globalReport) -Message "Consolidated audit report should use explicit project and date naming."
Assert-PathExists -Path (Join-Path $workspace "validation\consolidated_audit_result.json")
$globalReportText = Get-Content -LiteralPath $globalReport.FullName -Raw
Assert-True -Condition ($globalReportText.Contains("Couverture globale")) -Message "Consolidated report should expose global coverage."

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
