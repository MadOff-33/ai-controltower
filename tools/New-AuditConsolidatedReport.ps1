param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$ReportName = ""
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

function ConvertTo-SafeName {
  param([string]$Value)
  $safe = ($Value -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
  if ([string]::IsNullOrWhiteSpace($safe)) { return "project" }
  return $safe
}

function Test-TextMojibake {
  param([string]$Text)
  $markers = @([string][char]0x00C3, [string][char]0x00C2, [string][char]0x00E2, [string][char]0xFFFD)
  foreach ($marker in $markers) {
    if ($Text.Contains($marker)) { return $true }
  }
  return $false
}

function Add-PathItem {
  param([hashtable]$Map, [string]$Path)
  $normal = ($Path -replace "\\", "/").Trim("/")
  if (-not [string]::IsNullOrWhiteSpace($normal)) { $Map[$normal] = $true }
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$configPath = Join-Path $workspace "audit.config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "audit.config.json introuvable: $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

$reportsDir = Join-Path $workspace "reports"
$contextDir = Join-Path $workspace "context_packs"
$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $contextDir)) { throw "Dossier context_packs introuvable: $contextDir" }
$manifests = @(Get-ChildItem -LiteralPath $contextDir -File -Filter "*_manifest.json" | Sort-Object LastWriteTime)
if ($manifests.Count -eq 0) { throw "Aucun manifeste de contexte trouve dans: $contextDir" }

$includedMap = @{}
$knownMap = @{}
$lotRows = @()
foreach ($manifestFile in $manifests) {
  $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
  $lotIncluded = @($manifest.included | ForEach-Object { $_.path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $lotOmitted = @($manifest.omitted | ForEach-Object { $_.path } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  foreach ($path in $lotIncluded) {
    Add-PathItem -Map $includedMap -Path $path
    Add-PathItem -Map $knownMap -Path $path
  }
  foreach ($path in $lotOmitted) {
    Add-PathItem -Map $knownMap -Path $path
  }
  $lotRows += [ordered]@{
    lot = [string]$manifest.lot
    manifest = $manifestFile.FullName
    included = $lotIncluded.Count
    omitted = $lotOmitted.Count
  }
}

$totalFiles = $knownMap.Count
$includedFiles = $includedMap.Count
$omittedPaths = @($knownMap.Keys | Where-Object { -not $includedMap.ContainsKey($_) } | Sort-Object)
$omittedFiles = $omittedPaths.Count
$percent = if ($totalFiles -gt 0) { [math]::Round(($includedFiles * 100.0) / $totalFiles, 1) } else { 100 }
$status = if ($omittedFiles -eq 0) { "complete" } else { "partial" }

$projectPath = [string]$config.project_path
$projectLeaf = Split-Path -Leaf $projectPath
if ([string]::IsNullOrWhiteSpace($projectLeaf)) { $projectLeaf = "project" }
$projectSafe = ConvertTo-SafeName -Value $projectLeaf
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($ReportName)) {
  $ReportName = $projectSafe + "_audit_" + $stamp + "_global_report.md"
}
if ([System.IO.Path]::GetFileName($ReportName) -ne $ReportName) { throw "ReportName doit etre un nom de fichier simple." }
if (-not $ReportName.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) { $ReportName += ".md" }
$reportPath = Join-Path $reportsDir $ReportName

$sourceReports = @(Get-ChildItem -LiteralPath $reportsDir -File -Filter "*_report.md" | Where-Object { $_.Name -notlike "*_global_report.md" } | Sort-Object Name)
$sourceSections = @()
$encodingWarnings = @()
foreach ($source in $sourceReports) {
  $text = Get-Content -LiteralPath $source.FullName -Raw
  if (Test-TextMojibake -Text $text) { $encodingWarnings += $source.Name }
  $sourceSections += "## Source: " + $source.Name
  $sourceSections += ""
  $sourceSections += $text.Trim()
  $sourceSections += ""
}

$lines = @()
$lines += "# Audit global - " + $projectLeaf
$lines += ""
$lines += "| Champ | Valeur |"
$lines += "| --- | --- |"
$lines += '| Projet | `' + $projectPath + '` |'
$lines += '| Workspace | `' + $workspace + '` |'
$lines += "| Genere le | " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + " |"
$lines += "| Statut | " + $status + " |"
$lines += ""
$lines += "## Couverture globale"
$lines += ""
$lines += "- Fichiers couverts: " + $includedFiles + "/" + $totalFiles + " (" + $percent + "%)"
$lines += "- Fichiers hors contexte restant: " + $omittedFiles
$lines += "- Lots consolides: " + $manifests.Count
$lines += ""
if ($omittedFiles -gt 0) {
  $lines += "### Fichiers restant hors contexte"
  $lines += ""
  foreach ($path in ($omittedPaths | Select-Object -First 50)) {
    $lines += '- `' + $path + '`'
  }
  if ($omittedFiles -gt 50) { $lines += "- ... " + ($omittedFiles - 50) + " autre(s)" }
  $lines += ""
}
$lines += "## Lots sources"
$lines += ""
$lines += "| Lot | Inclus dans le lot | Omis apres le lot |"
$lines += "| --- | ---: | ---: |"
foreach ($row in $lotRows) {
  $lines += "| " + $row.lot + " | " + $row.included + " | " + $row.omitted + " |"
}
$lines += ""
if ($encodingWarnings.Count -gt 0) {
  $lines += "## Avertissements"
  $lines += ""
  $lines += "- Encodage suspect detecte dans: " + (($encodingWarnings | Sort-Object -Unique) -join ", ")
  $lines += "- Ces sources doivent etre relancees ou corrigees avant une correction automatique sans revue."
  $lines += ""
}
$lines += "## Synthese consolidee"
$lines += ""
if ($sourceReports.Count -eq 0) {
  $lines += "Aucun rapport source trouve dans reports/."
} else {
  $lines += "Les constats ci-dessous proviennent des rapports de lots. La couverture globale indique si tous les fichiers inventoriables ont ete presentes au modele au moins une fois."
}
$lines += ""
$lines += $sourceSections

Write-Utf8NoBom -Path $reportPath -Content (($lines -join "`r`n").TrimEnd() + "`r`n")

$result = [ordered]@{
  generated_at = (Get-Date).ToString("o")
  workspace = $workspace
  project_path = $projectPath
  report = $reportPath
  status = $status
  included_files = $includedFiles
  omitted_files = $omittedFiles
  total_files = $totalFiles
  percent = $percent
  manifests = $lotRows
  source_reports = @($sourceReports | ForEach-Object { $_.FullName })
  encoding_warnings = $encodingWarnings
}
Write-Utf8NoBom -Path (Join-Path $validationDir "consolidated_audit_result.json") -Content ($result | ConvertTo-Json -Depth 8)

Write-Host "=== Consolidated audit report created ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Report:    " + $reportPath)
Write-Host ("Coverage:  " + $includedFiles + "/" + $totalFiles + " (" + $percent + "%, " + $status + ")")
if ($encodingWarnings.Count -gt 0) {
  Write-Host ("Warnings:  encodage suspect dans " + (($encodingWarnings | Sort-Object -Unique) -join ", "))
}
Write-Host ""
Write-Host "Next command:"
Write-Host ("Relire ou telecharger le rapport global: " + $reportPath)
