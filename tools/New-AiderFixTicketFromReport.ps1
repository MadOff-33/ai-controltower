param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$ReportPath = "",
  [string]$TicketId = "",
  [string]$Title = "Fix depuis rapport d'audit",
  [string]$Goal = "Corriger un point identifie dans le rapport d'audit en respectant le perimetre du ticket.",
  [string[]]$EditableFiles = @(),
  [string[]]$VerificationCommands = @(),
  [string[]]$AcceptanceCriteria = @()
)

$ErrorActionPreference = "Stop"

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
  return $normalized
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$reportsDir = Join-Path $workspace "reports"
$snapshot = Join-Path $workspace "source_snapshot"
if (-not (Test-Path -LiteralPath $snapshot)) { throw "Snapshot introuvable: $snapshot" }

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $reportFile = Get-ChildItem -LiteralPath $reportsDir -File -Filter "*.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $reportFile) { throw "Aucun rapport trouve dans: $reportsDir" }
  $ReportPath = $reportFile.FullName
}
$report = (Resolve-Path -LiteralPath $ReportPath).ProviderPath
$reportText = Get-Content -LiteralPath $report -Raw

if ($EditableFiles.Count -eq 0) {
  $candidatePaths = @()
  $matches = [regex]::Matches($reportText, "([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.(py|ps1|js|ts|json|yaml|yml|md|txt)")
  foreach ($match in $matches) { $candidatePaths += $match.Value }
  foreach ($candidate in $candidatePaths | Select-Object -Unique) {
    $relative = ConvertTo-RelativeSafePath -PathValue $candidate
    if (Test-Path -LiteralPath (Join-Path $snapshot ($relative -replace "/", "\")) -PathType Leaf) {
      $EditableFiles = @($relative)
      break
    }
  }
}

if ($EditableFiles.Count -eq 0) {
  $firstSource = Get-ChildItem -LiteralPath $snapshot -Recurse -File | Where-Object { $_.Extension -in @(".py", ".ps1", ".js", ".ts", ".json", ".yaml", ".yml") } | Sort-Object FullName | Select-Object -First 1
  if ($null -eq $firstSource) { throw "Impossible de proposer un fichier editable depuis le snapshot." }
  $rootLength = $snapshot.TrimEnd("\").Length
  $EditableFiles = @(($firstSource.FullName.Substring($rootLength).TrimStart("\") -replace "\\", "/"))
}

if ([string]::IsNullOrWhiteSpace($TicketId)) {
  $TicketId = "fix_from_report_" + (Get-Date -Format "yyyyMMdd_HHmmss")
}

if ($AcceptanceCriteria.Count -eq 0) {
  $AcceptanceCriteria = @("Le changement reste limite aux fichiers editable_files.", "La validation ControlTower ne signale aucun fichier hors perimetre.")
}

$ticketScript = "C:\AI_ControlTower\tools\New-AiderFixTicket.ps1"
& $ticketScript -WorkspacePath $workspace -TicketId $TicketId -Title $Title -Goal $Goal -EditableFiles $EditableFiles -VerificationCommands $VerificationCommands -AcceptanceCriteria $AcceptanceCriteria

Write-Host ""
Write-Host "Report source:"
Write-Host $report
