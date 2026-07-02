param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$SkipDependencyCheck
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\ControlTowerCommon.ps1")

function Test-CommandAvailable {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

$requiredDirs = @("audits", "docs", "hermes_memory", "logs", "prompts", "templates", "tools")
foreach ($dir in $requiredDirs) {
  $path = Join-Path $Root $dir
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

$initHermes = Join-Path $Root "tools\Initialize-HermesMemory.ps1"
if (-not (Test-Path -LiteralPath $initHermes)) {
  throw "Initialize-HermesMemory.ps1 introuvable: $initHermes"
}
& $initHermes -MemoryRoot $HermesMemoryRoot | Out-Null

$headlessDir = Join-Path $Root "tools\headless"
if ((Test-Path -LiteralPath (Join-Path $headlessDir "package.json")) -and (Get-Command "npm" -ErrorAction SilentlyContinue)) {
  Push-Location $headlessDir
  try {
    & npm install
    & npx playwright install chromium
  } finally {
    Pop-Location
  }
} else {
  Write-Host "npm introuvable ou tools/headless absent: verification navigateur non installee."
}

$dependencies = @()
if (-not $SkipDependencyCheck) {
  foreach ($name in @("git", "powershell", "aider", "ollama")) {
    $dependencies += [ordered]@{ name = $name; available = (Test-CommandAvailable -Name $name) }
  }
}

$report = [ordered]@{
  installed_at = (Get-Date).ToString("o")
  root = $Root
  hermes_memory_root = $HermesMemoryRoot
  dependency_check_skipped = [bool]$SkipDependencyCheck
  dependencies = $dependencies
  next_commands = @(
    ("powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "tools\tests\Invoke-ControlTowerTestSuite.ps1") + "`""),
    ("powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "tools\Invoke-ControlTowerRun.ps1") + "`" -Mode Audit -ProjectPath `"C:\chemin\Projet`" -ValidateAfterDryRun")
  )
}

$reportPath = Join-Path $HermesMemoryRoot "install_report.json"
Write-Utf8NoBom -Path $reportPath -Content ($report | ConvertTo-Json -Depth 8)

Write-Host "=== ControlTower installed ==="
Write-Host ("Root:   " + $Root)
Write-Host ("Hermes: " + $HermesMemoryRoot)
Write-Host ("Report: " + $reportPath)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File `"" + (Join-Path $Root "tools\tests\Invoke-ControlTowerTestSuite.ps1") + "`"")
