param(
  [string]$MemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\ControlTowerCommon.ps1")

$central = Join-Path $MemoryRoot "central"
New-Item -ItemType Directory -Path $central -Force | Out-Null

$entries = Join-Path $central "entries.jsonl"
$index = Join-Path $central "index.json"
$guidance = Join-Path $central "guidance_cache.md"
$schema = Join-Path $central "schema.json"

if (-not (Test-Path -LiteralPath $entries)) {
  Write-Utf8NoBom -Path $entries -Content ""
}

if (-not (Test-Path -LiteralPath $index)) {
  Write-Utf8NoBom -Path $index -Content ([ordered]@{
    created_at = (Get-Date).ToString("o")
    updated_at = (Get-Date).ToString("o")
    entries_count = 0
    kinds = @{}
    categories = @{}
  } | ConvertTo-Json -Depth 8)
}

if (-not (Test-Path -LiteralPath $guidance)) {
  Write-Utf8NoBom -Path $guidance -Content "# Hermes central guidance`r`n`r`nAucune experience centrale enregistree pour le moment.`r`n"
}

if (-not (Test-Path -LiteralPath $schema)) {
  $templateSchema = (Join-Path (Split-Path -Parent $PSScriptRoot) "templates\hermes\central_memory.schema.json")
  if (Test-Path -LiteralPath $templateSchema) {
    Copy-Item -LiteralPath $templateSchema -Destination $schema -Force
  } else {
    Write-Utf8NoBom -Path $schema -Content "{}"
  }
}

Write-Host "=== Hermes memory initialized ==="
Write-Host ("MemoryRoot: " + $MemoryRoot)
Write-Host ("Central:    " + $central)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg (Join-Path (Split-Path -Parent $PSScriptRoot) "tools\Add-HermesMemoryEntry.ps1")) + " -MemoryRoot " + (Quote-Arg $MemoryRoot) + " -Kind experience -Category general -Summary " + (Quote-Arg "Nouvelle experience") + " -Source manual")
