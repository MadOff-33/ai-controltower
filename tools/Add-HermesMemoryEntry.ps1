param(
  [string]$MemoryRoot = "C:\AI_ControlTower\hermes_memory",

  [Parameter(Mandatory = $true)]
  [string]$Kind,

  [Parameter(Mandatory = $true)]
  [string]$Category,

  [Parameter(Mandatory = $true)]
  [string]$Summary,

  [Parameter(Mandatory = $true)]
  [string]$Source,

  [string]$Confidence = "medium",
  [string]$Status = "active",
  [string]$Lesson = "",
  [string[]]$Evidence = @(),
  [string[]]$SuggestedActions = @(),
  [string[]]$Tags = @(),
  [string]$RunLog = "",
  [string]$ContextJson = ""
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Update-HermesIndex {
  param([string]$EntriesPath, [string]$IndexPath)
  $kinds = @{}
  $categories = @{}
  $count = 0
  if (Test-Path -LiteralPath $EntriesPath) {
    foreach ($line in (Get-Content -LiteralPath $EntriesPath)) {
      if ([string]::IsNullOrWhiteSpace($line)) { continue }
      $entry = $line | ConvertFrom-Json
      $count++
      $kind = [string]$entry.kind
      $category = [string]$entry.category
      if (-not $kinds.ContainsKey($kind)) { $kinds[$kind] = 0 }
      if (-not $categories.ContainsKey($category)) { $categories[$category] = 0 }
      $kinds[$kind] = [int]$kinds[$kind] + 1
      $categories[$category] = [int]$categories[$category] + 1
    }
  }
  Write-Utf8NoBom -Path $IndexPath -Content ([ordered]@{
    updated_at = (Get-Date).ToString("o")
    entries_count = $count
    kinds = $kinds
    categories = $categories
  } | ConvertTo-Json -Depth 8)
}

$initScript = "C:\AI_ControlTower\tools\Initialize-HermesMemory.ps1"
if (Test-Path -LiteralPath $initScript) {
  & $initScript -MemoryRoot $MemoryRoot | Out-Null
}

$central = Join-Path $MemoryRoot "central"
$entries = Join-Path $central "entries.jsonl"
$index = Join-Path $central "index.json"

$id = "mem_" + (Get-Date -Format "yyyyMMdd_HHmmss_fff")
$context = $null
if (-not [string]::IsNullOrWhiteSpace($ContextJson)) {
  $context = $ContextJson | ConvertFrom-Json
}

$entry = [ordered]@{
  id = $id
  kind = $Kind
  category = $Category
  summary = $Summary
  source = $Source
  confidence = $Confidence
  status = $Status
  created_at = (Get-Date).ToString("o")
}
if ($Evidence.Count -gt 0) { $entry["evidence"] = $Evidence }
if (-not [string]::IsNullOrWhiteSpace($Lesson)) { $entry["lesson"] = $Lesson }
if ($SuggestedActions.Count -gt 0) { $entry["suggested_actions"] = $SuggestedActions }
if ($Tags.Count -gt 0) { $entry["tags"] = $Tags }
if (-not [string]::IsNullOrWhiteSpace($RunLog)) { $entry["run_log"] = $RunLog }
if ($null -ne $context) { $entry["context"] = $context }

$line = (($entry | ConvertTo-Json -Depth 12 -Compress) -join "")
[System.IO.File]::AppendAllText($entries, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
Update-HermesIndex -EntriesPath $entries -IndexPath $index

Write-Host "=== Hermes memory entry added ==="
Write-Host ("Id:       " + $id)
Write-Host ("Kind:     " + $Kind)
Write-Host ("Category: " + $Category)
