param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,

  [string]$WorkspaceRoot = "C:\AI_ControlTower\audits",
  [string]$AuditName = "",
  [string]$ProfilePath = "C:\AI_ControlTower\templates\audit_profiles\python-basic.yaml"
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

function Test-ExcludedPath {
  param(
    [string]$RelativePath,
    [string[]]$ExcludeDirs,
    [string[]]$ExcludeFiles,
    [string[]]$SensitiveNames
  )
  $normalized = ($RelativePath -replace "\\", "/").Trim("/")
  $lower = $normalized.ToLowerInvariant()
  $segments = $lower -split "/"
  foreach ($dir in $ExcludeDirs) {
    if ($segments -contains $dir.ToLowerInvariant()) { return $true }
  }
  $name = [System.IO.Path]::GetFileName($lower)
  foreach ($pattern in $ExcludeFiles) {
    if ($name -like $pattern.ToLowerInvariant()) { return $true }
  }
  foreach ($marker in $SensitiveNames) {
    if ($name -like "*$($marker.ToLowerInvariant())*") { return $true }
  }
  return $false
}

$project = Resolve-Path -LiteralPath $ProjectPath
$projectFull = $project.ProviderPath

if (-not (Test-Path -LiteralPath $WorkspaceRoot)) {
  New-Item -ItemType Directory -Path $WorkspaceRoot | Out-Null
}

if ([string]::IsNullOrWhiteSpace($AuditName)) {
  $AuditName = Split-Path -Path $projectFull -Leaf
}

$safeName = ($AuditName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "audit" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workspace = Join-Path $WorkspaceRoot ($stamp + "_" + $safeName)
$snapshot = Join-Path $workspace "source_snapshot"

New-Item -ItemType Directory -Path $workspace | Out-Null
New-Item -ItemType Directory -Path $snapshot | Out-Null
New-Item -ItemType Directory -Path (Join-Path $workspace "inventory") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $workspace "context_packs") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $workspace "prompts") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $workspace "reports") | Out-Null
New-Item -ItemType Directory -Path (Join-Path $workspace "validation") | Out-Null

$baseExcludeDirs = @(".git", ".hg", ".svn", ".venv", "venv", "env", ".env", "node_modules", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".cache", "dist", "build", "target", ".idea", ".vscode")
$baseExcludeFiles = @(".env", ".env.*", "*.pem", "*.key", "*.pfx", "*.sqlite", "*.sqlite3", "*.db", "*.exe", "*.dll", "*.bin", "*.zip", "*.7z", "*.tar", "*.gz", "*.pyc", "*.pyo")
$sensitiveNames = @("secret", "secrets", "password", "passwd", "token", "private_key")
$profileExcludeDirs = Get-ProfileList -Path $ProfilePath -Key "exclude_dirs"
$profileExcludeFiles = Get-ProfileList -Path $ProfilePath -Key "exclude_files"
$excludeDirs = @($baseExcludeDirs + $profileExcludeDirs | Select-Object -Unique)
$excludeFiles = @($baseExcludeFiles + $profileExcludeFiles | Select-Object -Unique)

$copied = 0
$skipped = 0
$rootLength = $projectFull.TrimEnd("\").Length

Get-ChildItem -LiteralPath $projectFull -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $relative = $_.FullName.Substring($rootLength).TrimStart("\")
  if (Test-ExcludedPath -RelativePath $relative -ExcludeDirs $excludeDirs -ExcludeFiles $excludeFiles -SensitiveNames $sensitiveNames) {
    $script:skipped++
    return
  }
  $dest = Join-Path $snapshot $relative
  $destDir = Split-Path -Path $dest -Parent
  if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
  $script:copied++
}

$config = [ordered]@{
  created_at = (Get-Date).ToString("o")
  project_path = $projectFull
  workspace_path = $workspace
  snapshot_path = $snapshot
  profile_path = $ProfilePath
  copied_files = $copied
  skipped_files = $skipped
  exclude_dirs = $excludeDirs
  exclude_files = $excludeFiles
  sensitive_name_markers = $sensitiveNames
}

Write-Utf8NoBom -Path (Join-Path $workspace "audit.config.json") -Content ($config | ConvertTo-Json -Depth 8)

Write-Host "=== Audit workspace created ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Snapshot:  " + $snapshot)
Write-Host ("Copied:    " + $copied)
Write-Host ("Skipped:   " + $skipped)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\New-ProjectInventory.ps1") + " -WorkspacePath " + (Quote-Arg $workspace))
