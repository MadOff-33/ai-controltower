param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$LotName,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath,

  [string]$ReportName = "",
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
$contextPack = (Resolve-Path -LiteralPath $ContextPackPath).ProviderPath
$reportsDir = Join-Path $workspace "reports"
$promptsDir = Join-Path $workspace "prompts"
$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
New-Item -ItemType Directory -Path $promptsDir -Force | Out-Null
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null

$safeLot = ($LotName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeLot)) { throw "LotName invalide." }
if ([string]::IsNullOrWhiteSpace($ReportName)) { $ReportName = $safeLot + "_report.md" }
$reportFileName = Split-Path -Path $ReportName -Leaf
if ($reportFileName -ne $ReportName) { throw "ReportName doit etre un nom de fichier simple, pas un chemin." }
$reportPath = Join-Path $reportsDir $reportFileName
if (-not (Test-Path -LiteralPath $reportPath)) {
  Write-Utf8NoBom -Path $reportPath -Content ("# Rapport $safeLot`r`n`r`n")
}

$messagePath = Join-Path $promptsDir ($safeLot + "_aider_message.md")
$message = @(
  "Tu dois utiliser uniquement le fichier fourni avec --read comme source factuelle.",
  "Le seul fichier editable est le rapport ouvert par Aider.",
  "Ecris dans le rapport une section: Couverture, Synthese, Constats, Incertitudes, Prochaines actions.",
  "N'invente pas de fichiers, de fonctions ou de comportements absents du contexte.",
  "Chaque constat factuel doit citer un chemin relatif present dans le contexte.",
  "Chaque constat doit fournir une preuve courte sous forme: chemin relatif + extrait exact entre backticks present dans le contexte.",
  "Ne conclus jamais sur un fichier liste comme omis ou non inclus; place-le seulement dans Incertitudes.",
  "N'ecris pas qu'un champ, port, fonction ou fichier est absent sans verifier que l'extrait n'apparait pas dans le contexte.",
  "Si le contexte ne permet pas de conclure, ecris explicitement l'incertitude.",
  "N'utilise pas de caracteres corrompus ou mojibake dans le rapport.",
  "Mets a jour le rapport maintenant."
) -join [Environment]::NewLine
Write-Utf8NoBom -Path $messagePath -Content $message

$workspaceRootLength = $workspace.TrimEnd("\").Length
$baseline = @()
Get-ChildItem -LiteralPath $workspace -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($workspaceRootLength).TrimStart("\") -replace "\\", "/"
  $baseline += [ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
}
Write-Utf8NoBom -Path (Join-Path $validationDir "baseline_files.json") -Content ($baseline | ConvertTo-Json -Depth 6)

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
  "--read", $contextPack,
  $reportPath,
  "--message-file", $messagePath
)
$display = "aider " + (($args | ForEach-Object { Quote-Arg $_ }) -join " ")

Write-Host "=== Aider audit command ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Report:    " + $reportPath)
Write-Host ("Context:   " + $contextPack)
Write-Host ""
Write-Host $display
Write-Host ""

if ($DryRun) {
  Write-Host "DryRun actif: Aider n'a pas ete lance."
} else {
  Enable-AiderUtf8Environment
  Push-Location $workspace
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
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Test-AiderOutput.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -ReportPath " + (Quote-Arg $reportPath) + " -ContextPackPath " + (Quote-Arg $contextPack))
