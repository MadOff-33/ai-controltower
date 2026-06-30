param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketId,

  [Parameter(Mandatory = $true)]
  [string]$Title,

  [Parameter(Mandatory = $true)]
  [string]$Goal,

  [Parameter(Mandatory = $true)]
  [string[]]$EditableFiles,

  [string[]]$ReadonlyFiles = @(),
  [string[]]$VerificationCommands = @(),
  [string[]]$AcceptanceCriteria = @()
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

function ConvertTo-RelativeSafePath {
  param([string]$PathValue)
  if ([string]::IsNullOrWhiteSpace($PathValue)) { throw "Chemin vide interdit." }
  if ([System.IO.Path]::IsPathRooted($PathValue)) { throw "Chemin absolu interdit: $PathValue" }
  $normalized = ($PathValue -replace "\\", "/").Trim("/")
  if ($normalized -match "(^|/)\.\.($|/)") { throw "Chemin parent interdit: $PathValue" }
  if ($normalized -match "^[a-zA-Z]:") { throw "Chemin absolu interdit: $PathValue" }
  return $normalized
}

function Add-YamlList {
  param([System.Collections.Generic.List[string]]$Lines, [string]$Key, [string[]]$Values)
  $Lines.Add($Key + ":") | Out-Null
  foreach ($value in $Values) {
    $escaped = $value.Replace('"', '\"')
    $Lines.Add('  - "' + $escaped + '"') | Out-Null
  }
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$snapshot = Join-Path $workspace "source_snapshot"
if (-not (Test-Path -LiteralPath $snapshot)) { throw "Snapshot introuvable: $snapshot" }

$safeId = ($TicketId -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeId)) { throw "TicketId invalide." }

$editable = @()
foreach ($file in $EditableFiles) {
  $relative = ConvertTo-RelativeSafePath -PathValue $file
  $absolute = Join-Path $snapshot ($relative -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Fichier editable introuvable dans le snapshot: $relative" }
  $editable += $relative
}

$readonly = @()
foreach ($file in $ReadonlyFiles) {
  $relative = ConvertTo-RelativeSafePath -PathValue $file
  $absolute = Join-Path $snapshot ($relative -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Fichier read-only introuvable dans le snapshot: $relative" }
  $readonly += $relative
}

$ticketDir = Join-Path $workspace "fix_tickets"
New-Item -ItemType Directory -Path $ticketDir -Force | Out-Null
$ticketPath = Join-Path $ticketDir ($safeId + ".yaml")

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("id: $safeId") | Out-Null
$lines.Add('title: "' + $Title.Replace('"', '\"') + '"') | Out-Null
$lines.Add('goal: "' + $Goal.Replace('"', '\"') + '"') | Out-Null
Add-YamlList -Lines $lines -Key "editable_files" -Values $editable
Add-YamlList -Lines $lines -Key "readonly_files" -Values $readonly
Add-YamlList -Lines $lines -Key "verification_commands" -Values $VerificationCommands
Add-YamlList -Lines $lines -Key "acceptance_criteria" -Values $AcceptanceCriteria
Add-YamlList -Lines $lines -Key "forbidden" -Values @("Do not edit files outside editable_files.", "Do not invent files, functions, routes, commands or APIs absent from the context.")

Write-Utf8NoBom -Path $ticketPath -Content ($lines -join [Environment]::NewLine)

Write-Host "=== Aider fix ticket created ==="
Write-Host ("Ticket: " + $ticketPath)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\New-FixContextPack.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -TicketPath " + (Quote-Arg $ticketPath))
