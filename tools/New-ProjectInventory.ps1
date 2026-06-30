param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath
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

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$configPath = Join-Path $workspace "audit.config.json"
if (-not (Test-Path -LiteralPath $configPath)) {
  throw "audit.config.json introuvable: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$snapshot = $config.snapshot_path
if (-not (Test-Path -LiteralPath $snapshot)) {
  throw "Snapshot introuvable: $snapshot"
}

$inventoryDir = Join-Path $workspace "inventory"
$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $inventoryDir -Force | Out-Null
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null

$rootLength = $snapshot.TrimEnd("\").Length
$items = @()
Get-ChildItem -LiteralPath $snapshot -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($rootLength).TrimStart("\") -replace "\\", "/"
  $items += [pscustomobject][ordered]@{
    path = $relative
    extension = $_.Extension.ToLowerInvariant()
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
    last_write_time = $_.LastWriteTimeUtc.ToString("o")
  }
}

$csv = $items | ConvertTo-Csv -NoTypeInformation
Write-Utf8NoBom -Path (Join-Path $inventoryDir "files.csv") -Content ($csv -join [Environment]::NewLine)
Write-Utf8NoBom -Path (Join-Path $inventoryDir "files.json") -Content ($items | ConvertTo-Json -Depth 6)

$byExt = $items | Group-Object extension | Sort-Object Count -Descending | ForEach-Object {
  $extName = $_.Name
  if ([string]::IsNullOrWhiteSpace($extName)) { $extName = "[no extension]" }
  "- {0}: {1}" -f $extName, $_.Count
}
$summary = @(
  "# Project inventory",
  "",
  ('Workspace: `{0}`' -f $workspace),
  ('Snapshot: `{0}`' -f $snapshot),
  ("Files: {0}" -f $items.Count),
  ("Bytes: {0}" -f (($items | Measure-Object -Property size_bytes -Sum).Sum)),
  "",
  "## Extensions",
  "",
  ($byExt -join [Environment]::NewLine)
) -join [Environment]::NewLine
Write-Utf8NoBom -Path (Join-Path $inventoryDir "summary.md") -Content $summary

$baseline = @()
$workspaceRootLength = $workspace.TrimEnd("\").Length
Get-ChildItem -LiteralPath $workspace -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($workspaceRootLength).TrimStart("\") -replace "\\", "/"
  $baseline += [pscustomobject][ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
}
Write-Utf8NoBom -Path (Join-Path $validationDir "baseline_files.json") -Content ($baseline | ConvertTo-Json -Depth 6)

Write-Host "=== Inventory created ==="
Write-Host ("Files: " + $items.Count)
Write-Host ("Inventory: " + $inventoryDir)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\New-ContextPack.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -LotName " + (Quote-Arg "lot1_config") + " -PromptPath " + (Quote-Arg "C:\AI_ControlTower\prompts\audit\lot1_config.md"))
