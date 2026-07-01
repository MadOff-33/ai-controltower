param(
  [string]$Path = "."
)

$ErrorActionPreference = "Stop"

Write-Host "=== Python tests ==="
Push-Location $Path
$exitCode = 0
try {
  if ((Test-Path ".\pytest.ini") -or (Test-Path ".\pyproject.toml") -or (Test-Path ".\tests")) {
    $venvPython = ".\.venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $venvPython) {
      $pythonExe = (Resolve-Path -LiteralPath $venvPython).ProviderPath
      $pythonArgs = @()
    } else {
      $python = Get-Command py -ErrorAction SilentlyContinue
      $pythonArgs = @("-3")
      if ($null -eq $python) {
        $python = Get-Command python -ErrorAction SilentlyContinue
        $pythonArgs = @()
      }
      if ($null -eq $python) { throw "Python est requis pour lancer pytest." }
      $pythonExe = $python.Source
    }
    & $pythonExe @pythonArgs -m pytest
    $exitCode = $LASTEXITCODE
  } else {
    Write-Host "Aucun setup pytest detecte."
  }
} finally {
  Pop-Location
}
exit $exitCode
