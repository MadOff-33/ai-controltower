param(
  [string]$MemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [int]$MaxItems = 8,
  [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\ControlTowerCommon.ps1")

$initScript = (Join-Path (Split-Path -Parent $PSScriptRoot) "tools\Initialize-HermesMemory.ps1")
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
  foreach ($line in (Get-Content -LiteralPath $entries -Encoding UTF8)) {
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

$correctionAttempts = @($items | Where-Object { $_.kind -eq "correction_attempt" } | Sort-Object created_at -Descending | Select-Object -First 50)
if ($correctionAttempts.Count -gt 0) {
  $lines.Add("") | Out-Null
  $lines.Add("## Taux de reussite de la correction automatique (50 dernieres tentatives)") | Out-Null
  $lines.Add("") | Out-Null
  $byCategory = $correctionAttempts | Group-Object category
  foreach ($group in $byCategory) {
    $fixed = @($group.Group | Where-Object { $_.context.outcome -eq "fixed" }).Count
    $total = $group.Group.Count
    $percent = if ($total -gt 0) { [Math]::Round(($fixed * 100.0 / $total), 0) } else { 0 }
    $lines.Add("- " + $group.Name + ": " + $fixed + "/" + $total + " (" + $percent + "%)") | Out-Null
  }
}

Write-Utf8NoBom -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
Write-Host "=== Hermes guidance generated ==="
Write-Host ("Guidance: " + $OutputPath)
