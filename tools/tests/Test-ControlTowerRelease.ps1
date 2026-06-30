param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$TempRoot = Join-Path $Root "hermes_lab\release test runs"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

function Remove-TestTree {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $base = [System.IO.Path]::GetFullPath((Join-Path $Root "hermes_lab")).TrimEnd("\")
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  Assert-True -Condition $full.StartsWith($base + "\", [System.StringComparison]::OrdinalIgnoreCase) -Message "Unsafe cleanup path: $full"
  Remove-Item -LiteralPath $full -Recurse -Force
}

Write-Host "=== Test ControlTower Release ==="

$required = @(
  "tools\Install-ControlTower.ps1",
  "tools\tests\Invoke-ControlTowerTestSuite.ps1",
  "docs\controltower_architecture.md",
  "docs\release_checklist.md",
  "docs\project_closure_report.md",
  "README.md",
  ".gitignore"
)

foreach ($relative in $required) {
  Assert-PathExists -Path (Join-Path $Root $relative)
}

$filesToCheck = @()
$filesToCheck += Get-ChildItem -LiteralPath (Join-Path $Root "tools") -Recurse -File -Include *.ps1
$filesToCheck += Get-ChildItem -LiteralPath (Join-Path $Root "docs") -File -Include *.md
$filesToCheck += Get-ChildItem -LiteralPath (Join-Path $Root "templates") -Recurse -File
$filesToCheck += Get-ChildItem -LiteralPath (Join-Path $Root "prompts") -Recurse -File

foreach ($file in $filesToCheck) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $file.FullName)
}

foreach ($script in (Get-ChildItem -LiteralPath (Join-Path $Root "tools") -Recurse -File -Filter *.ps1)) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $script.FullName)
}

Remove-TestTree -Path $TempRoot
$installRoot = Join-Path $TempRoot "Hermes Memory"
& (Join-Path $Root "tools\Install-ControlTower.ps1") -HermesMemoryRoot $installRoot -SkipDependencyCheck | Out-Null
Assert-PathExists -Path (Join-Path $installRoot "central\entries.jsonl")
Assert-PathExists -Path (Join-Path $installRoot "central\guidance_cache.md")
Assert-PathExists -Path (Join-Path $installRoot "install_report.json")

$suiteList = & (Join-Path $Root "tools\tests\Invoke-ControlTowerTestSuite.ps1") -List
$suiteText = ($suiteList -join "`n")
foreach ($name in @("Test-AiderReliabilityLayer.ps1", "Test-AiderFixReliability.ps1", "Test-ControlTowerOrchestrator.ps1", "Test-HermesMemory.ps1", "Test-ControlTowerRelease.ps1")) {
  Assert-True -Condition $suiteText.Contains($name) -Message ("Test suite missing " + $name)
}

Remove-TestTree -Path $TempRoot
Write-Host "All ControlTower release tests passed."
