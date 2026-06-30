param(
  [string]$Root = "C:\AI_ControlTower",
  [string]$HermesMemoryRoot = "C:\AI_ControlTower\hermes_memory",
  [switch]$SkipDependencyCheck
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

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
    'powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Invoke-ControlTowerTestSuite.ps1"',
    'powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "C:\chemin\Projet" -ValidateAfterDryRun'
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
Write-Host 'powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Invoke-ControlTowerTestSuite.ps1"'
