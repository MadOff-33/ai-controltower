param(
  [string]$Path = "."
)

Write-Host "=== Python tests ==="
Set-Location $Path

if (Test-Path ".\pytest.ini" -or Test-Path ".\pyproject.toml" -or Test-Path ".\tests") {
  py -3.12 -m pytest
} else {
  Write-Host "Aucun setup pytest détecté."
}
