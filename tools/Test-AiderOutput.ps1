param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$ReportPath,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath
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
$riskPattern = "(always|never|aucun|tous|impossible|n'existe pas|does not exist|no file|all files)"
$lines = $reportText -split "`r?`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  $hasRisk = $line -match $riskPattern
  $hasPathCitation = $line -match "([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+"
  if ($hasRisk -and -not $hasPathCitation) {
    $factualWarnings += [ordered]@{ line = $i + 1; text = $line.Trim() }
  }
}

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace = $workspace
  report = $report
  context_pack = $contextPack
  changes = $changes
  unauthorized_changes = $unauthorized
  ghost_findings = $ghostFindings
  factual_warnings = $factualWarnings
  passed = (($unauthorized.Count -eq 0) -and ($ghostFindings.Count -eq 0))
}
Write-Utf8NoBom -Path (Join-Path $validationDir "last_result.json") -Content ($result | ConvertTo-Json -Depth 8)

Write-Host "=== Aider output validation ==="
Write-Host ("Changes:              " + $changes.Count)
Write-Host ("Unauthorized changes: " + $unauthorized.Count)
Write-Host ("Ghost findings:       " + $ghostFindings.Count)
Write-Host ("Factual warnings:     " + $factualWarnings.Count)

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

Write-Host ""
if ($result.passed) {
  Write-Host "Validation passed."
  Write-Host "Next command:"
  Write-Host "Lancer le lot suivant ou relire le rapport dans reports/."
  exit 0
}

Write-Host "Validation failed. Corriger le rapport ou supprimer les fichiers non autorises, puis relancer Test-AiderOutput.ps1."
exit 1
