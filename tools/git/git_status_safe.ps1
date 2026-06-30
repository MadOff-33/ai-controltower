param(
  [string]$Path = "."
)

Write-Host "=== Git status safe ==="
git -C $Path status
