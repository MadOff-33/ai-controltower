$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$engine = Join-Path $Root "tools\Test-ProjectFunctional.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function New-Fixture {
  param([string]$Name)
  $path = Join-Path $Root ("hermes_lab\functional check fixtures\" + $Name)
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

Write-Host "=== Test-ProjectFunctional: webapp ok ==="
$fixture = New-Fixture -Name "webapp_ok"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><div id="app"></div><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "webapp" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: webapp missing DOM reference ==="
$fixture = New-Fixture -Name "webapp_missing_dom"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "webapp" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)
Assert-True -Condition ($result.summary.Contains("app")) -Message "Summary should mention the missing element id."

Write-Host "=== Test-ProjectFunctional: python syntax error ==="
$fixture = New-Fixture -Name "python_syntax_error"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def broken(:"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: python no tests ==="
$fixture = New-Fixture -Name "python_no_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)
Assert-True -Condition ($result.summary.Contains("aucun test")) -Message "Summary should be honest about no tests existing."

Write-Host "=== Test-ProjectFunctional: python failing tests ==="
$fixture = New-Fixture -Name "python_failing_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a - b`n"
New-Item -ItemType Directory -Path (Join-Path $fixture "tests") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture "tests\test_main.py") -Value "import sys, os`nsys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))`nfrom main import add`ndef test_add():`n    assert add(2, 3) == 5`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: python passing tests ==="
$fixture = New-Fixture -Name "python_passing_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
New-Item -ItemType Directory -Path (Join-Path $fixture "tests") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture "tests\test_main.py") -Value "import sys, os`nsys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))`nfrom main import add`ndef test_add():`n    assert add(2, 3) == 5`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: not verified (empty dir, desktop type) ==="
$fixture = New-Fixture -Name "not_verified"
Set-Content -LiteralPath (Join-Path $fixture "readme.txt") -Value "nothing recognizable here"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "desktop" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "not_verified") -Message ("Expected not_verified, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: auto-detect with no declared type (Fix mode simulation) ==="
$fixture = New-Fixture -Name "auto_detect_python"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok via auto-detection, got " + $result.status)

Write-Host ""
Write-Host "All Test-ProjectFunctional checks passed."
