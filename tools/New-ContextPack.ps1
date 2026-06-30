param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$LotName,

  [Parameter(Mandatory = $true)]
  [string]$PromptPath,

  [int]$MaxChars = 0
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

function Get-ProfileScalar {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$") {
      return $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return ""
}

function Get-ProfileList {
  param([string]$Path, [string]$Key)
  $items = @()
  if (-not (Test-Path -LiteralPath $Path)) { return $items }
  $lines = Get-Content -LiteralPath $Path
  $inKey = $false
  foreach ($line in $lines) {
    if ($line -match "^\s*$([regex]::Escape($Key))\s*:") {
      $inKey = $true
      continue
    }
    if ($inKey -and $line -match "^\S.*:") { break }
    if ($inKey -and $line -match "^\s*-\s*(.+?)\s*$") {
      $items += $Matches[1].Trim().Trim('"').Trim("'")
    }
  }
  return $items
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$configPath = Join-Path $workspace "audit.config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "audit.config.json introuvable: $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$snapshot = $config.snapshot_path
$profilePath = $config.profile_path

if ($MaxChars -le 0) {
  $profileLimit = Get-ProfileScalar -Path $profilePath -Key "default_max_chars"
  if ($profileLimit -match "^\d+$") { $MaxChars = [int]$profileLimit } else { $MaxChars = 45000 }
}

$allowedExtensions = Get-ProfileList -Path $profilePath -Key "allowed_extensions"
if ($allowedExtensions.Count -eq 0) {
  $allowedExtensions = @(".py", ".toml", ".ini", ".cfg", ".yaml", ".yml", ".json", ".md", ".txt", ".rst")
}
$allowedLookup = @{}
foreach ($ext in $allowedExtensions) { $allowedLookup[$ext.ToLowerInvariant()] = $true }

$safeLot = ($LotName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeLot)) { throw "LotName invalide." }

$prompt = Get-Content -LiteralPath $PromptPath -Raw
$contextDir = Join-Path $workspace "context_packs"
$promptDir = Join-Path $workspace "prompts"
New-Item -ItemType Directory -Path $contextDir -Force | Out-Null
New-Item -ItemType Directory -Path $promptDir -Force | Out-Null

$packPath = Join-Path $contextDir ($safeLot + "_pack.md")
$promptCopyPath = Join-Path $promptDir ($safeLot + "_prompt.md")
Write-Utf8NoBom -Path $promptCopyPath -Content $prompt

$rootLength = $snapshot.TrimEnd("\").Length
$included = @()
$omitted = @()
$sections = New-Object System.Collections.Generic.List[string]
$header = @(
  "# Context pack - $safeLot",
  "",
  "Ce fichier est la seule source read-only a fournir a Aider pour ce lot.",
  "Les chemins ci-dessous sont relatifs au snapshot et normalises avec `/`.",
  "",
  "## Prompt du lot",
  "",
  $prompt,
  "",
  "## Inventaire synthetique",
  "",
  (Get-Content -LiteralPath (Join-Path $workspace "inventory\summary.md") -Raw),
  "",
  "## Fichiers inclus",
  ""
) -join [Environment]::NewLine
$current = $header.Length

Get-ChildItem -LiteralPath $snapshot -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
  $relative = $_.FullName.Substring($rootLength).TrimStart("\") -replace "\\", "/"
  $ext = $_.Extension.ToLowerInvariant()
  if (-not $allowedLookup.ContainsKey($ext)) {
    $omitted += [ordered]@{ path = $relative; reason = "extension non incluse"; size_bytes = $_.Length }
    return
  }
  $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $content) { $content = "" }
  $block = @(
    "### $relative",
    "",
    '```text',
    $content,
    '```',
    ""
  ) -join [Environment]::NewLine
  if (($current + $block.Length) -gt $MaxChars) {
    $omitted += [ordered]@{ path = $relative; reason = "limite de caracteres"; size_bytes = $_.Length }
    return
  }
  $sections.Add($block) | Out-Null
  $current += $block.Length
  $included += [ordered]@{ path = $relative; size_bytes = $_.Length; chars = $block.Length }
}

$body = $sections -join [Environment]::NewLine
$footerLines = New-Object System.Collections.Generic.List[string]
$footerLines.Add("") | Out-Null
$footerLines.Add("## Fichiers omis") | Out-Null
$footerLines.Add("") | Out-Null
$omittedCount = $omitted.Count
$omittedWritten = 0
foreach ($item in $omitted) {
  $line = "- {0} ({1})" -f $item.path, $item.reason
  $candidateFooter = (($footerLines + @($line)) -join [Environment]::NewLine)
  $candidatePack = $header + $body + $candidateFooter
  if ($candidatePack.Length -gt $MaxChars) { break }
  $footerLines.Add($line) | Out-Null
  $omittedWritten++
}
if ($omittedWritten -lt $omittedCount) {
  $remaining = $omittedCount - $omittedWritten
  $summary = "- ... $remaining fichier(s) omis supplementaires dans le manifeste JSON."
  $candidateFooter = (($footerLines + @($summary)) -join [Environment]::NewLine)
  if (($header + $body + $candidateFooter).Length -le $MaxChars) {
    $footerLines.Add($summary) | Out-Null
  }
}

$pack = $header + $body + ($footerLines -join [Environment]::NewLine)
if ($pack.Length -gt $MaxChars) {
  throw "Le pack depasse la limite apres assemblage: $($pack.Length) / $MaxChars"
}
Write-Utf8NoBom -Path $packPath -Content $pack
Write-Utf8NoBom -Path (Join-Path $contextDir ($safeLot + "_manifest.json")) -Content ([ordered]@{
  lot = $safeLot
  max_chars = $MaxChars
  actual_chars = $pack.Length
  omitted_written_in_pack = $omittedWritten
  included = $included
  omitted = $omitted
} | ConvertTo-Json -Depth 8)

Write-Host "=== Context pack created ==="
Write-Host ("Pack:      " + $packPath)
Write-Host ("Chars:     " + $pack.Length + " / " + $MaxChars)
Write-Host ("Included:  " + $included.Count)
Write-Host ("Omitted:   " + $omitted.Count)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Start-AiderAudit.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -LotName " + (Quote-Arg $safeLot) + " -ContextPackPath " + (Quote-Arg $packPath) + " -DryRun")
