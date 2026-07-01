param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$Model = "ollama_chat/ornith:9b",
  [switch]$DryRun
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

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-OptionalText {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    return (Get-Content -LiteralPath $Path -Raw)
  }
  return ""
}

function Enable-AiderUtf8Environment {
  $script:PreviousPythonUtf8 = $env:PYTHONUTF8
  $script:PreviousPythonIoEncoding = $env:PYTHONIOENCODING
  $script:PreviousPythonLegacyWindowsStdio = $env:PYTHONLEGACYWINDOWSSTDIO
  $script:PreviousNoColor = $env:NO_COLOR
  $script:PreviousPyColors = $env:PY_COLORS
  $script:PreviousOutputEncoding = $OutputEncoding
  $script:PreviousConsoleOutputEncoding = [Console]::OutputEncoding

  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = $utf8
  $script:OutputEncoding = $utf8
  $env:PYTHONUTF8 = "1"
  $env:PYTHONIOENCODING = "utf-8"
  $env:PYTHONLEGACYWINDOWSSTDIO = "0"
  $env:NO_COLOR = "1"
  $env:PY_COLORS = "0"
}

function Restore-AiderUtf8Environment {
  if ($null -eq $script:PreviousPythonUtf8) { Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue } else { $env:PYTHONUTF8 = $script:PreviousPythonUtf8 }
  if ($null -eq $script:PreviousPythonIoEncoding) { Remove-Item Env:\PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $script:PreviousPythonIoEncoding }
  if ($null -eq $script:PreviousPythonLegacyWindowsStdio) { Remove-Item Env:\PYTHONLEGACYWINDOWSSTDIO -ErrorAction SilentlyContinue } else { $env:PYTHONLEGACYWINDOWSSTDIO = $script:PreviousPythonLegacyWindowsStdio }
  if ($null -eq $script:PreviousNoColor) { Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue } else { $env:NO_COLOR = $script:PreviousNoColor }
  if ($null -eq $script:PreviousPyColors) { Remove-Item Env:\PY_COLORS -ErrorAction SilentlyContinue } else { $env:PY_COLORS = $script:PreviousPyColors }
  if ($script:PreviousConsoleOutputEncoding) { [Console]::OutputEncoding = $script:PreviousConsoleOutputEncoding }
  if ($script:PreviousOutputEncoding) { $script:OutputEncoding = $script:PreviousOutputEncoding }
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$configPath = Join-Path $workspace "creation.config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "creation.config.json introuvable: $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$target = [string]$config.target_project_path
$brief = [string]$config.brief_path
$prompt = [string]$config.prompt_path
if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "Dossier cible introuvable: $target" }
if (-not (Test-Path -LiteralPath $brief -PathType Leaf)) { throw "Brief introuvable: $brief" }
if (-not (Test-Path -LiteralPath $prompt -PathType Leaf)) { throw "Prompt introuvable: $prompt" }

$promptsDir = Join-Path $workspace "prompts"
$validationDir = Join-Path $workspace "validation"
$reportsDir = Join-Path $workspace "reports"
New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null

$targetRootLength = $target.TrimEnd("\").Length
$baseline = @()
Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $relative = $_.FullName.Substring($targetRootLength).TrimStart("\") -replace "\\", "/"
  $baseline += [ordered]@{ path = $relative; size_bytes = $_.Length; sha256 = Get-FileHashSafe -Path $_.FullName }
}
Write-Utf8NoBom -Path (Join-Path $validationDir "creation_baseline.json") -Content ($baseline | ConvertTo-Json -Depth 6)

$messagePath = Join-Path $promptsDir "creation_aider_message.md"
$chatHistoryPath = Join-Path $workspace "creation_aider_chat_history.md"
$inputHistoryPath = Join-Path $workspace "creation_aider_input_history"
$llmHistoryPath = Join-Path $workspace "creation_aider_llm_history.md"
$promptText = Get-Content -LiteralPath $prompt -Raw
$briefText = Get-Content -LiteralPath $brief -Raw
$guidanceText = Get-OptionalText -Path "C:\AI_ControlTower\prompts\common\controltower_aider_guidance.md"
$hermesText = Get-OptionalText -Path "C:\AI_ControlTower\hermes_memory\central\guidance_cache.md"
$message = @(
  "## ControlTower guidance",
  "",
  $guidanceText,
  "",
  "## Hermes memory guidance",
  "",
  $hermesText,
  "",
  $promptText,
  "",
  "## Brief utilisateur",
  "",
  $briefText,
  "",
  "## Action",
  "",
  "Cree maintenant le projet complet dans le dossier courant.",
  "Tu peux creer les fichiers necessaires, mais tu dois rester dans le dossier courant.",
  "Ne cree aucun fichier interdit: .env, secrets, venv, .git, cache, db, exe, dll, archive.",
  "Termine par un README clair et une commande de verification."
) -join [Environment]::NewLine
Write-Utf8NoBom -Path $messagePath -Content $message

$reportPath = Join-Path $reportsDir "creation_report.md"
if (-not (Test-Path -LiteralPath $reportPath)) {
  Write-Utf8NoBom -Path $reportPath -Content ("# Rapport creation`r`n`r`n")
}

$editableFiles = @()
Get-ChildItem -LiteralPath $target -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $relative = $_.FullName.Substring($targetRootLength).TrimStart("\")
  $normalized = ($relative -replace "\\", "/").ToLowerInvariant()
  if ($normalized -match '(^|/)(\.git|\.venv|venv|env|node_modules|__pycache__|\.cache|dist|build)(/|$)') { return }
  if ([System.IO.Path]::GetFileName($normalized) -like ".env*") { return }
  $editableFiles += $_.FullName
}
if ($editableFiles.Count -eq 0) { throw "Aucun fichier editable trouve dans: $target" }

$args = @(
  "--model", $Model,
  "--no-git",
  "--no-gitignore",
  "--no-auto-commits",
  "--no-dirty-commits",
  "--no-pretty",
  "--no-stream",
  "--no-fancy-input",
  "--yes-always",
  "--no-restore-chat-history",
  "--max-chat-history-tokens", "200000",
  "--chat-history-file", $chatHistoryPath,
  "--input-history-file", $inputHistoryPath,
  "--llm-history-file", $llmHistoryPath,
  "--read", $brief
)
foreach ($file in $editableFiles) { $args += $file }
$args += @("--message-file", $messagePath)
$display = "aider " + (($args | ForEach-Object { Quote-Arg $_ }) -join " ")

Write-Host "=== Aider creation command ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Target:    " + $target)
Write-Host ("Brief:     " + $brief)
Write-Host ""
Write-Host $display
Write-Host ""

if ($DryRun) {
  Write-Host "DryRun actif: Aider n'a pas ete lance."
} else {
  Enable-AiderUtf8Environment
  Push-Location $target
  try {
    & aider @args
    if ($LASTEXITCODE -ne 0) { throw "Aider a retourne le code $LASTEXITCODE" }
  } finally {
    Pop-Location
    Restore-AiderUtf8Environment
  }
}

Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Test-AiderCreation.ps1") + " -WorkspacePath " + (Quote-Arg $workspace))
