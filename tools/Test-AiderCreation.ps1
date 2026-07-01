param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [switch]$RequireUsefulChanges
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

function Test-ForbiddenPath {
  param([string]$RelativePath)
  $normalized = ($RelativePath -replace "\\", "/").Trim("/")
  $lower = $normalized.ToLowerInvariant()
  $segments = $lower -split "/"
  $forbiddenDirs = @(".git", ".hg", ".svn", ".venv", "venv", "env", "node_modules", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".cache", "dist", "build")
  foreach ($dir in $forbiddenDirs) {
    if ($segments -contains $dir) { return $true }
  }
  $name = [System.IO.Path]::GetFileName($lower)
  if ($name -like ".aider*") { return $true }
  $forbiddenFiles = @(".env", ".env.*", "*.pem", "*.key", "*.pfx", "*.sqlite", "*.sqlite3", "*.db", "*.exe", "*.dll", "*.bin", "*.zip", "*.7z", "*.tar", "*.gz", "*.pyc", "*.pyo")
  foreach ($pattern in $forbiddenFiles) {
    if ($name -like $pattern) { return $true }
  }
  foreach ($marker in @("secret", "secrets", "password", "passwd", "token", "private_key")) {
    if ($name -like "*$marker*") { return $true }
  }
  return $false
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$configPath = Join-Path $workspace "creation.config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "creation.config.json introuvable: $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$target = [string]$config.target_project_path
$validationDir = Join-Path $workspace "validation"
$baselinePath = Join-Path $validationDir "creation_baseline.json"
if (-not (Test-Path -LiteralPath $baselinePath)) { throw "Baseline creation introuvable: $baselinePath" }

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$baselineMap = @{}
foreach ($item in @($baseline)) { $baselineMap[$item.path] = $item }

$targetRootLength = $target.TrimEnd("\").Length
$currentMap = @{}
Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $relative = $_.FullName.Substring($targetRootLength).TrimStart("\") -replace "\\", "/"
  $currentMap[$relative] = [pscustomobject][ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
}

$changes = @()
foreach ($path in $currentMap.Keys) {
  if (-not $baselineMap.ContainsKey($path)) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "created" }
  } elseif ($baselineMap[$path].sha256 -ne $currentMap[$path].sha256) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "modified" }
  }
}

$usefulChanges = @($changes | Where-Object {
  $name = [System.IO.Path]::GetFileName(([string]$_.path).ToLowerInvariant())
  -not ($name -like ".aider*")
})
foreach ($path in $baselineMap.Keys) {
  if (-not $currentMap.ContainsKey($path)) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "deleted" }
  }
}

$forbidden = @()
foreach ($path in $currentMap.Keys) {
  if (Test-ForbiddenPath -RelativePath $path) {
    $forbidden += [pscustomobject][ordered]@{ path = $path; reason = "forbidden_path" }
  }
}

$ghostMarkers = @("app.run()", "sys.exit(app.exec_())")
$ghostFindings = @()
foreach ($path in $currentMap.Keys) {
  $absolute = Join-Path $target ($path -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
  $extension = [System.IO.Path]::GetExtension($absolute).ToLowerInvariant()
  if (@(".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf") -contains $extension) { continue }
  $text = Get-Content -LiteralPath $absolute -Raw -ErrorAction SilentlyContinue
  foreach ($marker in $ghostMarkers) {
    if ($text.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      $ghostFindings += [pscustomobject][ordered]@{ path = $path; marker = $marker }
    }
  }
}

$readmePath = Join-Path $target "README.md"
$readmeOk = (Test-Path -LiteralPath $readmePath -PathType Leaf) -and ((Get-Item -LiteralPath $readmePath).Length -gt 40)
$usefulChangeOk = ((-not $RequireUsefulChanges) -or ($usefulChanges.Count -gt 0))
$passed = (($forbidden.Count -eq 0) -and $readmeOk -and ($currentMap.Keys.Count -gt 0) -and $usefulChangeOk)

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace_path = $workspace
  target_project_path = $target
  changes = $changes
  useful_changes = $usefulChanges
  forbidden_files = $forbidden
  ghost_findings = $ghostFindings
  readme_ok = $readmeOk
  require_useful_changes = [bool]$RequireUsefulChanges
  useful_change_ok = $usefulChangeOk
  passed = $passed
}
Write-Utf8NoBom -Path (Join-Path $validationDir "creation_result.json") -Content ($result | ConvertTo-Json -Depth 8)

Write-Host "=== Aider creation validation ==="
Write-Host ("Target files:     " + $currentMap.Keys.Count)
Write-Host ("Changes:          " + $changes.Count)
Write-Host ("Useful changes:   " + $usefulChanges.Count)
Write-Host ("Forbidden files:  " + $forbidden.Count)
Write-Host ("Ghost findings:   " + $ghostFindings.Count)
Write-Host ("README present:   " + $readmeOk)
if ($forbidden.Count -gt 0) {
  Write-Host ""
  Write-Host "Forbidden files:"
  $forbidden | ForEach-Object { Write-Host ("- " + $_.path) }
}
if (-not $usefulChangeOk) {
  Write-Host ""
  Write-Host "No useful generated project changes were detected."
}

if ($passed) {
  Write-Host "Validation passed."
  Write-Host ""
  Write-Host "Next command:"
  Write-Host "Ouvrir le dossier projet ou lancer les tests du projet genere."
  exit 0
}

Write-Host "Validation failed."
exit 1
