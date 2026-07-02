$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

$hermesFixture = Join-Path $Root "hermes_lab\reinforcement aggregation fixture\hermes_memory"
if (Test-Path -LiteralPath $hermesFixture) { Remove-Item -LiteralPath $hermesFixture -Recurse -Force }
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null

$addScript = Join-Path $Root "tools\Add-HermesMemoryEntry.ps1"
$fixedContext = (@{ outcome = "fixed"; target_file = "index.html"; attempt_number = 1 } | ConvertTo-Json -Compress)
$notFixedContext = (@{ outcome = "not_fixed"; target_file = "index.html"; attempt_number = 1 } | ConvertTo-Json -Compress)

& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "fixed 1" -ContextJson $fixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "fixed 2" -ContextJson $fixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "not fixed 1" -ContextJson $notFixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "browser_console" -Source "test" -Summary "not fixed 2" -ContextJson $notFixedContext | Out-Null

& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $hermesFixture | Out-Null
$guidance = Get-Content -LiteralPath (Join-Path $hermesFixture "central\guidance_cache.md") -Raw -Encoding UTF8

Assert-True -Condition ($guidance.Contains("Taux de reussite de la correction automatique")) -Message "Guidance should include the reinforcement section header."
Assert-True -Condition ($guidance.Contains("dom_reference_check: 2/3 (67%)")) -Message "dom_reference_check should show 2/3 (67%)."
Assert-True -Condition ($guidance.Contains("browser_console: 0/1 (0%)")) -Message "browser_console should show 0/1 (0%)."

Write-Host "All Test-HermesReinforcementAggregation checks passed."
