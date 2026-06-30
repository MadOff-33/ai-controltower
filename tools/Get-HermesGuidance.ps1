param(
  [string]$MemoryRoot = "C:\AI_ControlTower\hermes_memory",
  [int]$MaxItems = 8,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$initScript = "C:\AI_ControlTower\tools\Initialize-HermesMemory.ps1"
if (Test-Path -LiteralPath $initScript) {
  & $initScript -MemoryRoot $MemoryRoot | Out-Null
}

$central = Join-Path $MemoryRoot "central"
$entries = Join-Path $central "entries.jsonl"
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $central "guidance_cache.md"
}

$items = @()
if (Test-Path -LiteralPath $entries) {
  foreach ($line in (Get-Content -LiteralPath $entries)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $entry = $line | ConvertFrom-Json
    if ($entry.status -eq "archived") { continue }
    $items += $entry
  }
}

$selected = @($items | Sort-Object created_at -Descending | Select-Object -First $MaxItems)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Hermes central guidance") | Out-Null
$lines.Add("") | Out-Null

if ($selected.Count -eq 0) {
  $lines.Add("Aucune experience centrale active pour le moment.") | Out-Null
} else {
  foreach ($entry in $selected) {
    $text = [string]$entry.summary
    if ($entry.lesson) { $text = $text + " Lesson: " + [string]$entry.lesson }
    $lines.Add("- [" + [string]$entry.kind + "/" + [string]$entry.category + "] " + $text) | Out-Null
  }
}

Write-Utf8NoBom -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
Write-Host "=== Hermes guidance generated ==="
Write-Host ("Guidance: " + $OutputPath)
