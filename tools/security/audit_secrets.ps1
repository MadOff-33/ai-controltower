param(
  [string]$Path = "."
)

Write-Host "=== Secret audit basic ==="
Set-Location $Path

$patterns = @(
  "api_key",
  "apikey",
  "secret",
  "token",
  "password",
  "passwd",
  "private_key",
  "stripe",
  "woocommerce"
)

foreach ($pattern in $patterns) {
  Write-Host "--- Pattern: $pattern ---"
  Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch "\\.git\\" -and
      $_.FullName -notmatch "node_modules" -and
      $_.FullName -notmatch "__pycache__"
    } |
    Select-String -Pattern $pattern -SimpleMatch -ErrorAction SilentlyContinue |
    Select-Object Path, LineNumber, Line
}
