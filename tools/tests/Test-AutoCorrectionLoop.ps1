$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$loopScript = Join-Path $Root "tools\Invoke-AutoCorrectionLoop.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function New-Fixture {
  param([string]$Name)
  $path = Join-Path $Root ("hermes_lab\auto correction fixtures\" + $Name)
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

$hermesFixture = Join-Path $Root "hermes_lab\auto correction fixtures\hermes_memory"
if (Test-Path -LiteralPath $hermesFixture) { Remove-Item -LiteralPath $hermesFixture -Recurse -Force }
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null

Write-Host "=== Test-AutoCorrectionLoop: resolves on first attempt ==="
$fixture = New-Fixture -Name "resolves_first_attempt"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$fakeAider = Join-Path $Root "tools\tests\fixtures\fake-aider-fixes-html.ps1"
$json = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $fixture -ProjectType "webapp" -HermesMemoryRoot $hermesFixture -MaxAttempts 5 -AiderExecutable $fakeAider | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)
Assert-True -Condition ($result.auto_correction.resolved -eq $true) -Message "Expected resolved=true"
Assert-True -Condition ($result.auto_correction.attempts_used -eq 1) -Message ("Expected 1 attempt, got " + $result.auto_correction.attempts_used)
Assert-True -Condition ($result.summary.Contains("Corrige automatiquement apres 1 tentative")) -Message "Summary should mention attempt count"

Write-Host "=== Test-AutoCorrectionLoop: exhausts max attempts on an unfixable defect ==="
$fixture = New-Fixture -Name "exhausts_attempts"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$fakeAiderNoop = Join-Path $Root "tools\tests\fixtures\fake-aider-noop.ps1"
$json = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $fixture -ProjectType "webapp" -HermesMemoryRoot $hermesFixture -MaxAttempts 3 -AiderExecutable $fakeAiderNoop | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)
Assert-True -Condition ($result.auto_correction.resolved -eq $false) -Message "Expected resolved=false"
Assert-True -Condition ($result.auto_correction.attempts_used -eq 3) -Message ("Expected 3 attempts, got " + $result.auto_correction.attempts_used)
Assert-True -Condition ($result.summary.Contains("Echec apres 3 tentatives")) -Message "Summary should mention exhaustion"

Write-Host "=== Test-AutoCorrectionLoop: does not record false 'fixed' when recheck is not_verified ==="
$fixture = New-Fixture -Name "breaks_verification"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$fakeAiderBreaks = Join-Path $Root "tools\tests\fixtures\fake-aider-breaks-verification.ps1"
$json = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $fixture -ProjectType "webapp" -HermesMemoryRoot $hermesFixture -MaxAttempts 1 -AiderExecutable $fakeAiderBreaks | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.auto_correction.attempts_used -eq 1) -Message ("Expected 1 attempt, got " + $result.auto_correction.attempts_used)
$hermesEntriesPath = Join-Path $hermesFixture "central\entries.jsonl"
$entryLines = @(Get-Content -LiteralPath $hermesEntriesPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$correctionEntries = @($entryLines | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.kind -eq "correction_attempt" -and $_.category -eq "dom_reference_check" })
$lastEntry = $correctionEntries | Select-Object -Last 1
Assert-True -Condition ($null -ne $lastEntry) -Message "Expected a correction_attempt Hermes entry for dom_reference_check"
Assert-True -Condition ($lastEntry.context.outcome -eq "not_fixed") -Message ("Expected outcome=not_fixed when recheck is not_verified with empty checks, got " + $lastEntry.context.outcome)

Write-Host "=== Test-AutoCorrectionLoop: Get-TargetFileForCheck branches ==="
. $loopScript -ProjectPath (New-Fixture -Name "target_file_probe") -ProjectType "other" -HermesMemoryRoot $hermesFixture -MaxAttempts 0 2>$null | Out-Null
$domCheck = [pscustomobject]@{ name = "dom_reference_check"; status = "failed"; detail = "app.js: reference..." }
$functionalResult = [pscustomobject]@{ html_file = "index.html"; script_files = @("app.js") }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $domCheck -FunctionalResult $functionalResult
Assert-True -Condition ($target -eq (Join-Path "C:\fake\project" "index.html")) -Message ("dom_reference_check should target the HTML file, got " + $target)

$consoleCheck = [pscustomobject]@{ name = "browser_console"; status = "failed"; detail = "TypeError..." }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $consoleCheck -FunctionalResult $functionalResult
Assert-True -Condition ($target -eq (Join-Path "C:\fake\project" "app.js")) -Message ("browser_console should target the first script file, got " + $target)

$syntaxCheck = [pscustomobject]@{ name = "python_syntax"; status = "failed"; detail = "C:\fake\project\main.py" }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $syntaxCheck -FunctionalResult ([pscustomobject]@{})
Assert-True -Condition ($target -eq "C:\fake\project\main.py") -Message ("python_syntax should target the file from detail, got " + $target)

$testsCheck = [pscustomobject]@{ name = "python_tests"; status = "failed"; detail = "1 failed" }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $testsCheck -FunctionalResult ([pscustomobject]@{})
Assert-True -Condition ($null -eq $target) -Message "python_tests should return no single target file"

Write-Host ""
Write-Host "All Test-AutoCorrectionLoop checks passed."
