$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$toolsDir = Join-Path $Root "tools"
$testsDir = Join-Path $toolsDir "tests"

Write-Host "=== PowerShell encoding lint ==="

$files = Get-ChildItem -LiteralPath $toolsDir -Filter "*.ps1" -Recurse -File | Where-Object {
  -not $_.FullName.StartsWith($testsDir, [System.StringComparison]::OrdinalIgnoreCase)
}

$violations = @()
foreach ($file in $files) {
  $lineNumber = 0
  foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
    $lineNumber++
    if ($line -notmatch "Get-Content") { continue }
    if ($line -match "[\`"']\s*Get-Content") { continue }
    if ($line -match "-Encoding") { continue }
    $relative = $file.FullName.Substring($Root.Length + 1)
    $violations += ($relative + ":" + $lineNumber)
  }
}

if ($violations.Count -gt 0) {
  Write-Host "Violations (Get-Content without -Encoding):"
  $violations | ForEach-Object { Write-Host ("- " + $_) }
  throw ($violations.Count.ToString() + " Get-Content call(s) missing -Encoding in tools/*.ps1 (excluding tools/tests/).")
}

Write-Host "Encoding lint: 0 violations."
