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
$relativeContext = "context_packs/" + (Split-Path -Path $contextPack -Leaf)
$message = @(
  "/read-only $relativeContext",
  "",
  "Tu dois utiliser uniquement le fichier read-only ci-dessus comme source factuelle.",
  "Le seul fichier editable est le rapport deja ouvert par Aider dans `reports/`.",
  "N'invente pas de fichiers, de fonctions ou de comportements absents du contexte.",
  "Chaque constat factuel doit citer un chemin relatif present dans le contexte.",
  "Ecris ou mets a jour le rapport maintenant."
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

$args = @("--model", $Model, $reportPath, "--message-file", $messagePath)
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
  Push-Location $workspace
  try {
    & aider @args
    if ($LASTEXITCODE -ne 0) { throw "Aider a retourne le code $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}

Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Test-AiderOutput.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -ReportPath " + (Quote-Arg $reportPath) + " -ContextPackPath " + (Quote-Arg $contextPack))
