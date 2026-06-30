param(
  [switch]$List,
  [string]$Pattern = ""
)

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$Suites = @(
  "Test-AiderReliabilityLayer.ps1",
  "Test-AiderFixReliability.ps1",
  "Test-ControlTowerOrchestrator.ps1",
  "Test-HermesMemory.ps1",
  "Test-ControlTowerRelease.ps1"
)

if ($List) {
  $Suites | ForEach-Object { Write-Output $_ }
  exit 0
}

$selected = $Suites
if (-not [string]::IsNullOrWhiteSpace($Pattern)) {
  $selected = @($Suites | Where-Object { $_ -like $Pattern })
}
if ($selected.Count -eq 0) {
  throw "Aucune suite ne correspond au filtre: $Pattern"
}

$results = @()
foreach ($suite in $selected) {
  $path = Join-Path $Root ("tools\tests\" + $suite)
  if (-not (Test-Path -LiteralPath $path)) { throw "Suite introuvable: $path" }
  Write-Host ""
  Write-Host ("=== Running " + $suite + " ===")
  $started = Get-Date
  & powershell -ExecutionPolicy Bypass -File $path
  $code = $LASTEXITCODE
  $finished = Get-Date
  $results += [ordered]@{
    suite = $suite
    exit_code = $code
    started_at = $started.ToString("o")
    finished_at = $finished.ToString("o")
  }
  if ($code -ne 0) { throw "Suite failed: $suite" }
}

Write-Host ""
Write-Host "=== ControlTower test suite passed ==="
$results | ForEach-Object { Write-Host ("- " + $_.suite + ": exit " + $_.exit_code) }
