param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [int]$MaxChars = 30000
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

function Read-SimpleYaml {
  param([string]$Path)
  $data = @{}
  $current = ""
  function Convert-YamlValue {
    param([string]$Value)
    $text = $Value.Trim()
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
      $text = $text.Substring(1, $text.Length - 2)
    }
    return $text.Replace('\"', '"')
  }
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match "^\s*#") { continue }
    if ($line -match "^([A-Za-z0-9_]+):\s*(.*?)\s*$") {
      $current = $Matches[1]
      $value = Convert-YamlValue -Value $Matches[2]
      if ($value.Length -gt 0) { $data[$current] = $value } else { $data[$current] = @() }
      continue
    }
    if ($current -and $line -match "^\s*-\s*(.*?)\s*$") {
      $value = Convert-YamlValue -Value $Matches[1]
      $data[$current] = @($data[$current]) + $value
    }
  }
  return $data
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$ticket = (Resolve-Path -LiteralPath $TicketPath).ProviderPath
$snapshot = Join-Path $workspace "source_snapshot"
if (-not (Test-Path -LiteralPath $snapshot)) { throw "Snapshot introuvable: $snapshot" }

$data = Read-SimpleYaml -Path $ticket
$ticketId = $data["id"]
if ([string]::IsNullOrWhiteSpace($ticketId)) { throw "Ticket sans id: $ticket" }
$safeId = ($ticketId -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
$editable = @($data["editable_files"])
$readonly = @($data["readonly_files"])
$allFiles = @($editable + $readonly | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

$contextDir = Join-Path $workspace "fix_context_packs"
New-Item -ItemType Directory -Path $contextDir -Force | Out-Null
$packPath = Join-Path $contextDir ($safeId + "_pack.md")
$manifestPath = Join-Path $contextDir ($safeId + "_manifest.json")

$ticketText = Get-Content -LiteralPath $ticket -Raw
$sections = New-Object System.Collections.Generic.List[string]
$header = @(
  "# Fix context pack - $safeId",
  "",
  "Ce pack est read-only. Les seuls fichiers editables sont ceux du ticket.",
  "",
  "## Ticket",
  "",
  '```yaml',
  $ticketText,
  '```',
  "",
  "## Files"
) -join [Environment]::NewLine
$current = $header.Length
$included = @()
$omitted = @()

foreach ($relative in $allFiles) {
  $normalized = ($relative -replace "\\", "/").Trim("/")
  $absolute = Join-Path $snapshot ($normalized -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
    $omitted += [pscustomobject][ordered]@{ path = $normalized; reason = "missing" }
    continue
  }
  $content = Get-Content -LiteralPath $absolute -Raw
  $block = @(
    "",
    "### $normalized",
    "",
    '```text',
    $content,
    '```'
  ) -join [Environment]::NewLine
  if (($current + $block.Length) -gt $MaxChars) {
    $omitted += [pscustomobject][ordered]@{ path = $normalized; reason = "max_chars" }
    continue
  }
  $sections.Add($block) | Out-Null
  $current += $block.Length
  $included += [pscustomobject][ordered]@{ path = $normalized; chars = $block.Length }
}

$pack = $header + ($sections -join [Environment]::NewLine)
Write-Utf8NoBom -Path $packPath -Content $pack
Write-Utf8NoBom -Path $manifestPath -Content ([ordered]@{
  ticket = $safeId
  max_chars = $MaxChars
  actual_chars = $pack.Length
  included = $included
  omitted = $omitted
} | ConvertTo-Json -Depth 8)

Write-Host "=== Fix context pack created ==="
Write-Host ("Pack: " + $packPath)
Write-Host ("Chars: " + $pack.Length + " / " + $MaxChars)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Start-AiderFix.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -TicketPath " + (Quote-Arg $ticket) + " -ContextPackPath " + (Quote-Arg $packPath) + " -DryRun")
