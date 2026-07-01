param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$Scripts = @(
  "tools\New-AuditWorkspace.ps1",
  "tools\New-ProjectInventory.ps1",
  "tools\New-ContextPack.ps1",
  "tools\Start-AiderAudit.ps1",
  "tools\Test-AiderOutput.ps1",
  "tools\Invoke-AiderAuditPipeline.ps1"
)
$DeliveredFiles = @(
  "docs\aider_reliability_layer_spec.md",
  "docs\aider_operating_manual.md",
  "docs\controltower_reliability_v1_1_spec.md",
  "templates\audit_profiles\python-basic.yaml",
  "prompts\common\controltower_aider_guidance.md",
  "prompts\audit\lot1_config.md",
  "prompts\audit\lot2_architecture.md"
) + $Scripts

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

function Assert-PathNotExists {
  param([string]$Path)
  Assert-True -Condition (-not (Test-Path -LiteralPath $Path)) -Message "Unexpected path exists: $Path"
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

function Get-LatestWorkspace {
  param([string]$WorkspaceRoot)
  return (Get-ChildItem -LiteralPath $WorkspaceRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

function Remove-TestTree {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $base = [System.IO.Path]::GetFullPath((Join-Path $Root "hermes_lab")).TrimEnd("\")
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  Assert-True -Condition $full.StartsWith($base + "\", [System.StringComparison]::OrdinalIgnoreCase) -Message "Unsafe cleanup path: $full"
  Remove-Item -LiteralPath $full -Recurse -Force
}

Write-Host "=== Test Aider Reliability Layer ==="

foreach ($relative in $Scripts) {
  $path = Join-Path $Root $relative
  Assert-PathExists -Path $path
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

foreach ($relative in $DeliveredFiles) {
  $path = Join-Path $Root $relative
  Assert-PathExists -Path $path
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $path)
}

$testRoot = Join-Path $Root "hermes_lab\reliability test runs"
$project = Join-Path $testRoot "Project With Spaces"
$workspaceRoot = Join-Path $testRoot "Audit Workspaces"
Remove-TestTree -Path $testRoot
New-Item -ItemType Directory -Path $project | Out-Null
New-Item -ItemType Directory -Path (Join-Path $project "pkg") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $project ".git") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $project "__pycache__") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $project "pyproject.toml"), "[project]`nname = `"fixture`"`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project "pkg\core.py"), "def add(a, b):`n    return a + b`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project "README.md"), "# Fixture`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project ".env"), "TOKEN=do-not-copy`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project "data.db"), "fake-db`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project ".git\config"), "[core]`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $project "__pycache__\core.pyc"), "compiled`n", (New-Object System.Text.UTF8Encoding($false)))

& (Join-Path $Root "tools\Invoke-AiderAuditPipeline.ps1") `
  -ProjectPath $project `
  -WorkspaceRoot $workspaceRoot `
  -AuditName "Fixture With Spaces" `
  -LotName "lot1_config" `
  -PromptPath (Join-Path $Root "prompts\audit\lot1_config.md") `
  -MaxChars 12000 `
  -ValidateAfterDryRun

$workspace = Get-LatestWorkspace -WorkspaceRoot $workspaceRoot
Assert-PathExists -Path (Join-Path $workspace "audit.config.json")
Assert-PathExists -Path (Join-Path $workspace "inventory\files.json")
Assert-PathExists -Path (Join-Path $workspace "context_packs\lot1_config_pack.md")
Assert-PathExists -Path (Join-Path $workspace "reports\lot1_config_report.md")
Assert-PathExists -Path (Join-Path $workspace "validation\baseline_files.json")
Assert-PathExists -Path (Join-Path $workspace "validation\pipeline_result.json")

$snapshot = Join-Path $workspace "source_snapshot"
Assert-PathNotExists -Path (Join-Path $snapshot ".env")
Assert-PathNotExists -Path (Join-Path $snapshot "data.db")
Assert-PathNotExists -Path (Join-Path $snapshot ".git\config")
Assert-PathNotExists -Path (Join-Path $snapshot "__pycache__\core.pyc")

$pack = Join-Path $workspace "context_packs\lot1_config_pack.md"
$report = Join-Path $workspace "reports\lot1_config_report.md"
$packText = Get-Content -LiteralPath $pack -Raw
Assert-True -Condition ($packText.Length -le 12000) -Message ("Context pack exceeds configured MaxChars: " + $packText.Length)
$manifest = Get-Content -LiteralPath (Join-Path $workspace "context_packs\lot1_config_manifest.json") -Raw | ConvertFrom-Json
Assert-True -Condition ($null -ne $manifest.coverage) -Message "Context pack manifest should expose coverage summary."
Assert-True -Condition ($manifest.coverage.status -match "complete|partial") -Message "Context pack manifest should expose explicit coverage status."
Invoke-ExpectFailure -Name "draft report rejected in normal validation" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $report -ContextPackPath $pack
}
$outsideReport = Join-Path $workspace "not_reports.md"
[System.IO.File]::WriteAllText($outsideReport, "# Outside`n", (New-Object System.Text.UTF8Encoding($false)))
Invoke-ExpectFailure -Name "report outside reports" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $outsideReport -ContextPackPath $pack -AllowDraftReport
}
Remove-Item -LiteralPath $outsideReport -Force

& (Join-Path $Root "tools\Start-AiderAudit.ps1") -WorkspacePath $workspace -LotName "lot1_config" -ContextPackPath $pack -DryRun | Out-Null
$auditMessage = Get-Content -LiteralPath (Join-Path $workspace "prompts\lot1_config_aider_message.md") -Raw
Assert-True -Condition ($auditMessage.Contains("ControlTower Aider guidance")) -Message "Audit message should include shared ControlTower guidance."
Assert-True -Condition ($auditMessage.Contains("Hermes central guidance")) -Message "Audit message should include Hermes guidance."
$startAuditText = Get-Content -LiteralPath (Join-Path $Root "tools\Start-AiderAudit.ps1") -Raw
Assert-True -Condition ($startAuditText.Contains('"--no-git"')) -Message "Aider audit must not attach to the ControlTower git repo."
Assert-True -Condition ($startAuditText.Contains('"--read"')) -Message "Aider audit must pass the context pack as CLI read-only file."
Assert-True -Condition ($startAuditText.Contains('"--no-pretty"')) -Message "Aider audit must use non-interactive friendly output."
Assert-True -Condition (-not $startAuditText.Contains("/read-only")) -Message "Aider audit message should not rely on slash commands."
Assert-True -Condition ($startAuditText.Contains("PYTHONUTF8")) -Message "Aider audit must force Python UTF-8 mode on Windows."
Assert-True -Condition ($startAuditText.Contains("PYTHONIOENCODING")) -Message "Aider audit must force UTF-8 stdout/stderr on Windows."
$badOutput = Join-Path $workspace "context_packs\unexpected.md"
[System.IO.File]::WriteAllText($badOutput, "not allowed`n", (New-Object System.Text.UTF8Encoding($false)))
Invoke-ExpectFailure -Name "unauthorized output" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $report -ContextPackPath $pack -AllowDraftReport
}
Remove-Item -LiteralPath $badOutput -Force

& (Join-Path $Root "tools\Start-AiderAudit.ps1") -WorkspacePath $workspace -LotName "lot1_config" -ContextPackPath $pack -DryRun | Out-Null
Add-Content -LiteralPath $report -Encoding UTF8 -Value "`nLe point d'entree est main()."
Invoke-ExpectFailure -Name "ghost marker" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $report -ContextPackPath $pack
}

& (Join-Path $Root "tools\Start-AiderAudit.ps1") -WorkspacePath $workspace -LotName "lot1_config" -ContextPackPath $pack -DryRun | Out-Null
[System.IO.File]::WriteAllText($report, @"
# Rapport lot1_config

## Constats

| Severite | Chemin | Constat | Preuve |
| --- | --- | --- | --- |
| CRITIQUE | pyproject.toml | Le champ `smtp_password` existe dans la configuration. | `pyproject.toml` |
| MOYEN | pkg/core.py | La fonction `add` est absente du fichier. | `pkg/core.py` |

RÃ©sumÃ© corrompu.
"@, (New-Object System.Text.UTF8Encoding($false)))
Add-Content -LiteralPath $report -Encoding UTF8 -Value (([string][char]0x00C3) + ([string][char]0x00A9) + " direct marker.")
Invoke-ExpectFailure -Name "factual validator rejects missing fields, false absence and mojibake" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $report -ContextPackPath $pack
}

$omittedReport = @"
# Rapport lot1_config

## Constats

| Severite | Chemin | Constat | Preuve |
| --- | --- | --- | --- |
| HAUT | missing/file.py | Ce fichier omis contient une anomalie critique. | `missing/file.py` |
"@
[System.IO.File]::WriteAllText($report, $omittedReport, (New-Object System.Text.UTF8Encoding($false)))
Invoke-ExpectFailure -Name "factual validator rejects findings about files outside context" -Command {
  & (Join-Path $Root "tools\Test-AiderOutput.ps1") -WorkspacePath $workspace -ReportPath $report -ContextPackPath $pack
}

$fakeBin = Join-Path $testRoot "fake aider bin"
New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
$fakeAider = Join-Path $fakeBin "aider.cmd"
[System.IO.File]::WriteAllText($fakeAider, "@echo off`r`necho fake aider no changes`r`nexit /b 0`r`n", (New-Object System.Text.UTF8Encoding($false)))
$oldPath = $env:PATH
try {
  $env:PATH = $fakeBin + ";" + $oldPath
  Invoke-ExpectFailure -Name "pipeline fails when aider leaves draft report" -Command {
    & (Join-Path $Root "tools\Invoke-AiderAuditPipeline.ps1") `
      -ProjectPath $project `
      -WorkspaceRoot $workspaceRoot `
      -AuditName "Fake Aider No Report" `
      -LotName "lot1_config" `
      -PromptPath (Join-Path $Root "prompts\audit\lot1_config.md") `
      -MaxChars 12000 `
      -RunAider
  }
} finally {
  $env:PATH = $oldPath
}

Remove-TestTree -Path $testRoot

$pipelineText = Get-Content -LiteralPath (Join-Path $Root "tools\Invoke-AiderAuditPipeline.ps1") -Raw
Assert-True -Condition ($pipelineText.Contains("Invoke-PipelineStep")) -Message "Audit pipeline helper missing."
Assert-True -Condition ($pipelineText.Contains("LASTEXITCODE")) -Message "Audit pipeline must propagate failing child scripts."

Write-Host "All reliability layer tests passed."
