param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectName,

  [Parameter(Mandatory = $true)]
  [string]$ParentPath,

  [Parameter(Mandatory = $true)]
  [string]$Brief,

  [string]$ProjectType = "python-basic",
  [string]$WorkspaceRoot = "C:\AI_ControlTower\creation_workspaces",
  [string]$PromptPath = "C:\AI_ControlTower\prompts\creation\new_project.md",
  [switch]$AllowExisting
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

function Write-IfMissing {
  param([string]$Path, [string]$Content)
  if (-not (Test-Path -LiteralPath $Path)) {
    $dir = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Utf8NoBom -Path $Path -Content $Content
  }
}

if ($ProjectName -match '[\\/:*?"<>|]') { throw "ProjectName ne doit pas contenir de separateur ou caractere interdit Windows." }
$safeName = ($ProjectName -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeName)) { throw "ProjectName invalide." }
if ([string]::IsNullOrWhiteSpace($Brief)) { throw "Brief obligatoire." }

if (-not (Test-Path -LiteralPath $ParentPath)) {
  New-Item -ItemType Directory -Path $ParentPath -Force | Out-Null
}
$parent = (Resolve-Path -LiteralPath $ParentPath).ProviderPath
$target = Join-Path $parent $safeName
if ((Test-Path -LiteralPath $target) -and (-not $AllowExisting)) {
  $existing = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)
  if ($existing.Count -gt 0) { throw "Le dossier projet existe deja et n'est pas vide: $target" }
}
New-Item -ItemType Directory -Path $target -Force | Out-Null

New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workspace = Join-Path $WorkspaceRoot ($stamp + "_" + $safeName)
New-Item -ItemType Directory -Path $workspace -Force | Out-Null
foreach ($dir in @("prompts", "reports", "validation")) {
  New-Item -ItemType Directory -Path (Join-Path $workspace $dir) -Force | Out-Null
}

$briefPath = Join-Path $workspace "project_brief.md"
$briefText = @(
  "# Brief projet",
  "",
  "- Nom: $ProjectName",
  "- Type: $ProjectType",
  "- Dossier cible: $target",
  "- Cree: $((Get-Date).ToString("o"))",
  "",
  "## Demande",
  "",
  $Brief
) -join [Environment]::NewLine
Write-Utf8NoBom -Path $briefPath -Content $briefText

$readmePath = Join-Path $target "README.md"
if (-not (Test-Path -LiteralPath $readmePath)) {
  Write-Utf8NoBom -Path $readmePath -Content ("# $ProjectName`r`n`r`nProjet initialise par AI ControlTower. Le contenu sera complete par Aider.`r`n")
}

if ($ProjectType -like "python*") {
  Write-IfMissing -Path (Join-Path $target "pyproject.toml") -Content (@(
    "[project]",
    "name = `"$safeName`"",
    "version = `"0.1.0`"",
    "description = `"Projet initialise par AI ControlTower`"",
    "requires-python = `">=3.10`"",
    "",
    "[tool.pytest.ini_options]",
    "testpaths = [`"tests`"]"
  ) -join [Environment]::NewLine)
  Write-IfMissing -Path (Join-Path $target "src\app.py") -Content (@(
    "def main():",
    "    return `"AI ControlTower project ready`"",
    "",
    "",
    "if __name__ == `"__main__`":",
    "    print(main())"
  ) -join [Environment]::NewLine)
  Write-IfMissing -Path (Join-Path $target "tests\test_app.py") -Content (@(
    "from src.app import main",
    "",
    "",
    "def test_main_returns_message():",
    "    assert main()"
  ) -join [Environment]::NewLine)
} elseif ($ProjectType -eq "webapp") {
  Write-IfMissing -Path (Join-Path $target "index.html") -Content (@(
    "<!doctype html>",
    "<html lang=`"fr`">",
    "<head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`"><title>$ProjectName</title><link rel=`"stylesheet`" href=`"styles.css`"></head>",
    "<body><main id=`"app`"><h1>$ProjectName</h1></main><script src=`"app.js`"></script></body>",
    "</html>"
  ) -join [Environment]::NewLine)
  Write-IfMissing -Path (Join-Path $target "styles.css") -Content "body { font-family: system-ui, sans-serif; margin: 0; padding: 24px; }"
  Write-IfMissing -Path (Join-Path $target "app.js") -Content "document.querySelector('#app').dataset.ready = 'true';"
} else {
  Write-IfMissing -Path (Join-Path $target "notes.md") -Content "# Notes`r`n`r`nBase de travail creee par AI ControlTower.`r`n"
}

$config = [ordered]@{
  created_at = (Get-Date).ToString("o")
  project_name = $ProjectName
  safe_name = $safeName
  project_type = $ProjectType
  parent_path = $parent
  target_project_path = $target
  workspace_path = $workspace
  prompt_path = $PromptPath
  brief_path = $briefPath
}
Write-Utf8NoBom -Path (Join-Path $workspace "creation.config.json") -Content ($config | ConvertTo-Json -Depth 8)

Write-Host "=== Creation workspace created ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Target:    " + $target)
Write-Host ("Brief:     " + $briefPath)
Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Start-AiderCreation.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -DryRun")
