param(
  [string]$MemoryRoot = "C:\AI_ControlTower\hermes_memory"
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Quote-Arg {
  param([string]$Value)
  return '"' + ($Value -replace '"', '\"') + '"'
}

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
  $templateSchema = "C:\AI_ControlTower\templates\hermes\central_memory.schema.json"
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
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Add-HermesMemoryEntry.ps1") + " -MemoryRoot " + (Quote-Arg $MemoryRoot) + " -Kind experience -Category general -Summary " + (Quote-Arg "Nouvelle experience") + " -Source manual")
