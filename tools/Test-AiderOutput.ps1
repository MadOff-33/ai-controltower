param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath,

  [switch]$AllowDraftReport
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-UnderDirectory {
  param([string]$Path, [string]$Directory)
  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  $fullDir = [System.IO.Path]::GetFullPath($Directory).TrimEnd("\")
  return ($fullPath -eq $fullDir -or $fullPath.StartsWith($fullDir + "\", [System.StringComparison]::OrdinalIgnoreCase))
}

function Get-ContextManifestPath {
  param([string]$ContextPack)
  $dir = Split-Path -Parent $ContextPack
  $leaf = [System.IO.Path]::GetFileName($ContextPack)
  $manifestLeaf = $leaf -replace "_pack\.md$", "_manifest.json"
  $candidate = Join-Path $dir $manifestLeaf
  if (Test-Path -LiteralPath $candidate) { return $candidate }
  return ""
}

function Get-CodeSpans {
  param([string]$Text)
  $items = @()
  foreach ($match in [regex]::Matches($Text, '`([^`]{1,120})`')) {
    $items += $match.Groups[1].Value
  }
  return $items
}

function Test-FindingLine {
  param([string]$Line)
  $trimmed = $Line.Trim()
  if ($trimmed -match "^\|\s*(CRITIQUE|HAUT|MOYEN|BAS|LOW|MEDIUM|HIGH|CRITICAL)\s*\|") { return $true }
  if ($trimmed -match "^\-\s*(CRITIQUE|HAUT|MOYEN|BAS|LOW|MEDIUM|HIGH|CRITICAL)\b") { return $true }
  return $false
}

function Get-PathMentions {
  param([string]$Line, [object[]]$KnownPaths)
  $mentions = @()
  foreach ($path in $KnownPaths) {
    if ($Line.IndexOf($path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $mentions += $path
    }
  }
  foreach ($match in [regex]::Matches($Line, '([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+')) {
    $candidate = ($match.Value -replace "\\", "/").Trim()
    if ($candidate -notmatch '\.(py|json|csv|md|txt|toml|yaml|yml|ini|cfg|spec|ps1)$') { continue }
    if ($candidate -and -not ($mentions -contains $candidate)) { $mentions += $candidate }
  }
  return $mentions
}

function Get-PrimaryFindingPath {
  param([string]$Line)
  $trimmed = $Line.Trim()
  if ($trimmed.StartsWith("|")) {
    $parts = @($trimmed.Split("|") | ForEach-Object { $_.Trim() })
    if ($parts.Count -ge 4 -and $parts[2]) { return $parts[2] }
  }
  return ""
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$report = (Resolve-Path -LiteralPath $ReportPath).ProviderPath
$contextPack = (Resolve-Path -LiteralPath $ContextPackPath).ProviderPath
$reportsDir = Join-Path $workspace "reports"
$validationDir = Join-Path $workspace "validation"
$baselinePath = Join-Path $validationDir "baseline_files.json"

if (-not (Test-Path -LiteralPath $baselinePath)) { throw "Baseline introuvable: $baselinePath" }
if (-not (Test-UnderDirectory -Path $report -Directory $reportsDir)) { throw "Rapport hors dossier reports/: $report" }

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$baselineMap = @{}
foreach ($item in $baseline) { $baselineMap[$item.path] = $item }

$workspaceRootLength = $workspace.TrimEnd("\").Length
$current = @()
$currentMap = @{}
Get-ChildItem -LiteralPath $workspace -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($workspaceRootLength).TrimStart("\") -replace "\\", "/"
  $entry = [ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
  $current += $entry
  $currentMap[$relative] = $entry
}

$changes = @()
foreach ($path in $currentMap.Keys) {
  if (-not $baselineMap.ContainsKey($path)) {
    $changes += [ordered]@{ path = $path; change = "created" }
  } elseif ($baselineMap[$path].sha256 -ne $currentMap[$path].sha256) {
    $changes += [ordered]@{ path = $path; change = "modified" }
  }
}
foreach ($path in $baselineMap.Keys) {
  if (-not $currentMap.ContainsKey($path)) {
    $changes += [ordered]@{ path = $path; change = "deleted" }
  }
}

$unauthorized = @()
foreach ($change in $changes) {
  $absolute = Join-Path $workspace ($change.path -replace "/", "\")
  $allowed = (Test-UnderDirectory -Path $absolute -Directory $reportsDir) -or (Test-UnderDirectory -Path $absolute -Directory $validationDir)
  if (-not $allowed) { $unauthorized += $change }
}

$reportText = Get-Content -LiteralPath $report -Raw
$contextText = Get-Content -LiteralPath $contextPack -Raw
$contextManifestPath = Get-ContextManifestPath -ContextPack $contextPack
$contextManifest = $null
$includedPaths = @()
$omittedPaths = @()
$includedContent = @{}
if ($contextManifestPath) {
  $contextManifest = Get-Content -LiteralPath $contextManifestPath -Raw | ConvertFrom-Json
  $includedPaths = @($contextManifest.included | ForEach-Object { $_.path })
  $omittedPaths = @($contextManifest.omitted | ForEach-Object { $_.path })
  $configPathForSnapshot = Join-Path $workspace "audit.config.json"
  if (Test-Path -LiteralPath $configPathForSnapshot) {
    $snapshotRoot = (Get-Content -LiteralPath $configPathForSnapshot -Raw | ConvertFrom-Json).snapshot_path
    foreach ($path in $includedPaths) {
      $absolute = Join-Path $snapshotRoot ($path -replace "/", "\")
      if (Test-Path -LiteralPath $absolute -PathType Leaf) {
        $includedContent[$path] = Get-Content -LiteralPath $absolute -Raw -ErrorAction SilentlyContinue
      }
    }
  }
}
$normalizedReport = ($reportText -replace "\s+", " ").Trim()
$draftReport = ($normalizedReport -match "^# Rapport [A-Za-z0-9_.-]+$")
$ghostMarkers = @("main()", "app.run()", "sys.exit(app.exec_())")
$ghostFindings = @()
foreach ($marker in $ghostMarkers) {
  if ($reportText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $contextText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    $ghostFindings += $marker
  }
}

$configPath = Join-Path $workspace "audit.config.json"
if (Test-Path -LiteralPath $configPath) {
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if ($reportText.IndexOf($config.project_path, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
    $ghostFindings += "absolute project path"
  }
}

$factualWarnings = @()
$factualErrors = @()
$mojibakeFindings = @()
$outOfContextFindings = @()
$missingEvidenceFindings = @()
$falseAbsenceFindings = @()
$mojibakeMarkers = @("Ã", "Â", "â", "�")
foreach ($marker in $mojibakeMarkers) {
  if ($reportText.Contains($marker)) {
    $mojibakeFindings += $marker
  }
}
$riskPattern = "(always|never|aucun|tous|impossible|n'existe pas|does not exist|no file|all files)"
$lines = $reportText -split "`r?`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  $hasRisk = $line -match $riskPattern
  $hasPathCitation = $line -match "([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"
  if ($hasRisk -and -not $hasPathCitation) {
    $factualWarnings += [ordered]@{ line = $i + 1; text = $line.Trim() }
  }
  if (-not (Test-FindingLine -Line $line)) { continue }
  $lineNumber = $i + 1
  $pathMentions = Get-PathMentions -Line $line -KnownPaths ($includedPaths + $omittedPaths)
  $primaryPath = Get-PrimaryFindingPath -Line $line
  $includedMention = @()
  if ($primaryPath -and ($includedPaths -contains $primaryPath)) {
    $includedMention = @($primaryPath)
  } else {
    $includedMention = @($pathMentions | Where-Object { $includedPaths -contains $_ } | Select-Object -First 1)
  }
  foreach ($path in $pathMentions) {
    if (-not ($includedPaths -contains $path)) {
      $outOfContextFindings += [ordered]@{ line = $lineNumber; path = $path; text = $line.Trim() }
    }
  }
  if ($includedMention.Count -eq 0) { continue }
  $pathForEvidence = $includedMention[0]
  $fileText = [string]$includedContent[$pathForEvidence]
  $spans = @(Get-CodeSpans -Text $line | Where-Object { $_ -ne $pathForEvidence -and $_ -notmatch "^[A-Za-z0-9_. -]+/[A-Za-z0-9_. /-]+$" })
  if ($spans.Count -eq 0) {
    $missingEvidenceFindings += [ordered]@{ line = $lineNumber; path = $pathForEvidence; evidence = ""; reason = "preuve exacte manquante"; text = $line.Trim() }
  }
  foreach ($span in $spans) {
    if ($fileText.IndexOf($span, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
      $missingEvidenceFindings += [ordered]@{ line = $lineNumber; path = $pathForEvidence; evidence = $span; reason = "extrait absent du fichier cite"; text = $line.Trim() }
    }
    if ($line -match "(absent|absence|manquant|n.existe pas|non present|pas present)" -and $fileText.IndexOf($span, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $falseAbsenceFindings += [ordered]@{ line = $lineNumber; path = $pathForEvidence; evidence = $span; text = $line.Trim() }
    }
  }
}

$factualErrors = @($mojibakeFindings + $outOfContextFindings + $missingEvidenceFindings + $falseAbsenceFindings)

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace = $workspace
  report = $report
  context_pack = $contextPack
  changes = $changes
  unauthorized_changes = $unauthorized
  ghost_findings = $ghostFindings
  factual_warnings = $factualWarnings
  factual_errors = $factualErrors
  mojibake_findings = $mojibakeFindings
  out_of_context_findings = $outOfContextFindings
  missing_evidence_findings = $missingEvidenceFindings
  false_absence_findings = $falseAbsenceFindings
  coverage = $(if ($contextManifest) { $contextManifest.coverage } else { $null })
  draft_report = $draftReport
  allow_draft_report = [bool]$AllowDraftReport
  passed = (($unauthorized.Count -eq 0) -and ($ghostFindings.Count -eq 0) -and ($factualErrors.Count -eq 0) -and ((-not $draftReport) -or $AllowDraftReport))
}
Write-Utf8NoBom -Path (Join-Path $validationDir "last_result.json") -Content ($result | ConvertTo-Json -Depth 8)

Write-Host "=== Aider output validation ==="
Write-Host ("Changes:              " + $changes.Count)
Write-Host ("Unauthorized changes: " + $unauthorized.Count)
Write-Host ("Ghost findings:       " + $ghostFindings.Count)
Write-Host ("Factual warnings:     " + $factualWarnings.Count)
Write-Host ("Factual errors:       " + $factualErrors.Count)
Write-Host ("Draft report:         " + $draftReport)
if ($contextManifest -and $contextManifest.coverage) {
  Write-Host ("Coverage:             " + $contextManifest.coverage.included_files + "/" + $contextManifest.coverage.total_files + " files (" + $contextManifest.coverage.status + ")")
}

if ($unauthorized.Count -gt 0) {
  Write-Host ""
  Write-Host "Unauthorized files:"
  $unauthorized | ForEach-Object { Write-Host ("- " + $_.change + ": " + $_.path) }
}
if ($ghostFindings.Count -gt 0) {
  Write-Host ""
  Write-Host "Ghost markers:"
  $ghostFindings | ForEach-Object { Write-Host ("- " + $_) }
}
if ($factualWarnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Factual warnings to review:"
  $factualWarnings | Select-Object -First 10 | ForEach-Object { Write-Host ("- line " + $_.line + ": " + $_.text) }
}
if ($factualErrors.Count -gt 0) {
  Write-Host ""
  Write-Host "Factual errors:"
  if ($mojibakeFindings.Count -gt 0) { Write-Host ("- mojibake markers: " + (($mojibakeFindings | Select-Object -Unique) -join ", ")) }
  $outOfContextFindings | Select-Object -First 10 | ForEach-Object { Write-Host ("- line " + $_.line + ": file outside context: " + $_.path) }
  $missingEvidenceFindings | Select-Object -First 10 | ForEach-Object { Write-Host ("- line " + $_.line + ": evidence not found in " + $_.path + ": " + $_.evidence) }
  $falseAbsenceFindings | Select-Object -First 10 | ForEach-Object { Write-Host ("- line " + $_.line + ": false absence in " + $_.path + ": " + $_.evidence) }
}
if ($draftReport -and -not $AllowDraftReport) {
  Write-Host ""
  Write-Host "Draft report detected: Aider has not produced audit content yet."
}

Write-Host ""
if ($result.passed) {
  Write-Host "Validation passed."
  Write-Host "Next command:"
  Write-Host "Lancer le lot suivant ou relire le rapport dans reports/."
  exit 0
}

Write-Host "Validation failed. Corriger le rapport ou supprimer les fichiers non autorises, puis relancer Test-AiderOutput.ps1."
exit 1
