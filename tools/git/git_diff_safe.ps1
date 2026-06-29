param(
  [string]$Path = "."
)

Write-Host "=== Git diff safe ==="
git -C $Path diff --stat
git -C $Path diff
