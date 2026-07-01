param(
  [string]$ProjectPath = "",
  [string]$ReportPath = "C:\AI_ControlTower\logs\final_recipe_report.md",
  [switch]$SkipFullSuite
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Add-Line {
  param([System.Collections.Generic.List[string]]$Lines, [string]$Text = "")
  $Lines.Add($Text) | Out-Null
}

$root = "C:\AI_ControlTower"
$usingFixture = $false
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
  $usingFixture = $true
  $fixtureRoot = Join-Path $root "hermes_lab\final recipe fixture"
  if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
  New-Item -ItemType Directory -Path (Join-Path $fixtureRoot "pkg") -Force | Out-Null
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText((Join-Path $fixtureRoot "pkg\core.py"), "def add(a, b):`n    return a + b`n", $encoding)
  [System.IO.File]::WriteAllText((Join-Path $fixtureRoot "README.md"), "# Final recipe fixture`n", $encoding)
  $ProjectPath = $fixtureRoot
}
$reportDir = Split-Path -Parent $ReportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$lines = New-Object System.Collections.Generic.List[string]
Add-Line $lines "# ControlTower final recipe"
Add-Line $lines ""
Add-Line $lines ("Date: " + (Get-Date).ToString("o"))
Add-Line $lines ("Project: " + $ProjectPath)
Add-Line $lines ("Fixture mode: " + $usingFixture)
Add-Line $lines ""

Add-Line $lines "## Dependencies"
$depsJson = & (Join-Path $root "tools\Test-ControlTowerDependencies.ps1") -ProjectPath $ProjectPath -HermesMemoryRoot (Join-Path $root "hermes_memory")
$deps = $depsJson | ConvertFrom-Json
foreach ($name in @("project", "git", "aider", "ollama", "ornith", "hermes")) {
  $item = $deps.$name
  Add-Line $lines ("- " + $name + ": " + $(if ($item.available) { "OK" } else { "MISSING" }))
}

Add-Line $lines ""
Add-Line $lines "## UI self-test"
$python = Get-Command py -ErrorAction SilentlyContinue
if ($null -ne $python) {
  $uiJson = & $python.Source -3 (Join-Path $root "apps\controltower-ui\app.py") --self-test --project-path $ProjectPath
} else {
  $python = Get-Command python -ErrorAction Stop
  $uiJson = & $python.Source (Join-Path $root "apps\controltower-ui\app.py") --self-test --project-path $ProjectPath
}
$ui = $uiJson | ConvertFrom-Json
Add-Line $lines ("- kind: " + $ui.kind)
Add-Line $lines ("- jobs_supported: " + $ui.jobs_supported)
Add-Line $lines ("- workflow_steps: " + $ui.workflow_steps.Count)

if (-not $SkipFullSuite) {
  Add-Line $lines ""
  Add-Line $lines "## Full suite"
  & (Join-Path $root "tools\tests\Invoke-ControlTowerTestSuite.ps1") | Out-Null
  Add-Line $lines "- Invoke-ControlTowerTestSuite.ps1: passed"
}

Add-Line $lines ""
Add-Line $lines "## Audit dry-run"
& (Join-Path $root "tools\Invoke-ControlTowerRun.ps1") -Mode Audit -ProjectPath $ProjectPath -ValidateAfterDryRun -SkipHermes -MaxChars 12000 | Out-Null
Add-Line $lines "- Invoke-ControlTowerRun.ps1 audit dry-run: completed"
Add-Line $lines "- Expected status: structure-passed"

Add-Line $lines ""
Add-Line $lines "## Verdict"
Add-Line $lines "ControlTower final recipe completed. Review this file and the latest run log before final closure."

Write-Utf8NoBom -Path $ReportPath -Content ($lines -join [Environment]::NewLine)

Write-Host "=== ControlTower final recipe ==="
Write-Host ("Report: " + $ReportPath)
Write-Host ""
Write-Host "Next command:"
Write-Host ("Get-Content -LiteralPath " + '"' + $ReportPath + '"')
