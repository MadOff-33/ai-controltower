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

function Get-SuspiciousPathReasons {
  param([string]$RelativePath)
  $reasons = @()
  $normalized = ($RelativePath -replace "\\", "/").Trim("/")
  $name = [System.IO.Path]::GetFileName($normalized)
  $lowerName = $name.ToLowerInvariant()
  $lowerPath = $normalized.ToLowerInvariant()
  if ($name -match "[\u2500-\u257F]") { $reasons += "tree_art_path" }
  if ($name -match "#") { $reasons += "comment_in_filename" }
  if ($name -match "^\s*(open|cd|dir|ls|cat|type|mkdir|copy|move|del|rm)\s+") { $reasons += "command_like_filename" }
  if ($null -ne (Find-Mojibake -Text $lowerPath)) { $reasons += "mojibake_path" }
  if ($lowerName -match "\s{2,}") { $reasons += "excessive_spacing_filename" }
  return $reasons
}

function Test-TextExtension {
  param([string]$Path)
  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($extension)) { return $false }
  return @(".txt", ".md", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".py", ".ps1", ".js", ".ts", ".jsx", ".tsx", ".html", ".htm", ".css", ".scss", ".xml", ".svg", ".csv") -contains $extension
}

function Find-Mojibake {
  param([string]$Text)
  $patterns = @(
    ([string][char]0x00C3),
    ([string][char]0x00C2),
    ([string][char]0xFFFD),
    (([string][char]0x00E2) + ([string][char]0x20AC)),
    (([string][char]0x00F0) + ([string][char]0x0178))
  )
  foreach ($pattern in $patterns) {
    $index = $Text.IndexOf($pattern, [System.StringComparison]::Ordinal)
    if ($index -ge 0) {
      $start = [Math]::Max(0, $index - 24)
      $length = [Math]::Min(80, $Text.Length - $start)
      return [pscustomobject][ordered]@{
        marker = $pattern
        excerpt = ($Text.Substring($start, $length) -replace "\r?\n", " ")
      }
    }
  }
  return $null
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
$suspiciousFiles = @()
foreach ($path in $currentMap.Keys) {
  if (Test-ForbiddenPath -RelativePath $path) {
    $forbidden += [pscustomobject][ordered]@{ path = $path; reason = "forbidden_path" }
  }
  $pathReasons = @(Get-SuspiciousPathReasons -RelativePath $path)
  foreach ($reason in $pathReasons) {
    $suspiciousFiles += [pscustomobject][ordered]@{ path = $path; reason = $reason }
  }
}

$ghostMarkers = @("app.run()", "sys.exit(app.exec_())")
$ghostFindings = @()
$encodingFindings = @()
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
  if ((Test-TextExtension -Path $absolute) -and ($text.Length -gt 0)) {
    $mojibake = Find-Mojibake -Text $text
    if ($null -ne $mojibake) {
      $encodingFindings += [pscustomobject][ordered]@{
        path = $path
        marker = $mojibake.marker
        excerpt = $mojibake.excerpt
      }
    }
  }
}

$readmePath = Join-Path $target "README.md"
$readmeOk = (Test-Path -LiteralPath $readmePath -PathType Leaf) -and ((Get-Item -LiteralPath $readmePath).Length -gt 40)
$usefulChangeOk = ((-not $RequireUsefulChanges) -or ($usefulChanges.Count -gt 0))
$passed = (($forbidden.Count -eq 0) -and ($suspiciousFiles.Count -eq 0) -and ($encodingFindings.Count -eq 0) -and $readmeOk -and ($currentMap.Keys.Count -gt 0) -and $usefulChangeOk)

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace_path = $workspace
  target_project_path = $target
  changes = $changes
  useful_changes = $usefulChanges
  forbidden_files = $forbidden
  suspicious_files = $suspiciousFiles
  ghost_findings = $ghostFindings
  encoding_findings = $encodingFindings
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
Write-Host ("Suspicious files: " + $suspiciousFiles.Count)
Write-Host ("Ghost findings:   " + $ghostFindings.Count)
Write-Host ("Encoding issues:  " + $encodingFindings.Count)
Write-Host ("README present:   " + $readmeOk)
if ($forbidden.Count -gt 0) {
  Write-Host ""
  Write-Host "Forbidden files:"
  $forbidden | ForEach-Object { Write-Host ("- " + $_.path) }
}
if ($suspiciousFiles.Count -gt 0) {
  Write-Host ""
  Write-Host "Suspicious files:"
  $suspiciousFiles | ForEach-Object { Write-Host ("- " + $_.path + " (" + $_.reason + ")") }
}
if ($encodingFindings.Count -gt 0) {
  Write-Host ""
  Write-Host "Encoding issues:"
  $encodingFindings | ForEach-Object { Write-Host ("- " + $_.path + " marker=" + $_.marker) }
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
