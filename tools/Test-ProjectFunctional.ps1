param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,

  [string]$ProjectType = ""
)

$ErrorActionPreference = "Stop"

function Get-PythonExe {
  param([string]$ProjectPath)
  $venvPython = Join-Path $ProjectPath ".venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $venvPython) {
    return @{ exe = (Resolve-Path -LiteralPath $venvPython).ProviderPath; args = @() }
  }
  $python = Get-Command py -ErrorAction SilentlyContinue
  if ($null -ne $python) { return @{ exe = $python.Source; args = @("-3") } }
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($null -ne $python) { return @{ exe = $python.Source; args = @() } }
  return $null
}

function Test-PythonProject {
  param([string]$ProjectPath)
  $pyFiles = @(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "*.py" -ErrorAction SilentlyContinue | Where-Object {
    $_.FullName -notmatch '\\(\.venv|venv|__pycache__|\.git)\\'
  })
  if ($pyFiles.Count -eq 0) {
    return [ordered]@{ status = "not_verified"; summary = "Aucun fichier Python trouve, rien a verifier."; checks = @() }
  }
  $python = Get-PythonExe -ProjectPath $ProjectPath
  if ($null -eq $python) {
    return [ordered]@{ status = "not_verified"; summary = "Python n'est pas disponible sur ce poste, la verification a ete ignoree."; checks = @() }
  }
  $checks = @()
  $syntaxErrors = @()
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  foreach ($file in $pyFiles) {
    & $python.exe @($python.args) -m py_compile $file.FullName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $syntaxErrors += $file.FullName }
  }
  $ErrorActionPreference = $previousErrorActionPreference
  $checks += [ordered]@{ name = "python_syntax"; status = $(if ($syntaxErrors.Count -eq 0) { "ok" } else { "failed" }); detail = ($syntaxErrors -join ", ") }
  if ($syntaxErrors.Count -gt 0) {
    return [ordered]@{ status = "failed"; summary = "Le code contient une erreur qui empeche meme de le lire: " + $syntaxErrors[0]; checks = $checks }
  }
  $hasTests = (Test-Path -LiteralPath (Join-Path $ProjectPath "tests")) -or `
    (@(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "test_*.py" -ErrorAction SilentlyContinue).Count -gt 0) -or `
    (@(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "*_test.py" -ErrorAction SilentlyContinue).Count -gt 0)
  if (-not $hasTests) {
    $checks += [ordered]@{ name = "python_tests"; status = "ok"; detail = "Aucun test trouve." }
    return [ordered]@{ status = "ok"; summary = "Le code compile sans erreur, mais aucun test n'a ete trouve pour verifier le comportement."; checks = $checks }
  }
  Push-Location $ProjectPath
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $testOutput = & $python.exe @($python.args) -m pytest 2>&1
    $testExit = $LASTEXITCODE
  } finally {
    Pop-Location
    $ErrorActionPreference = $previousErrorActionPreference
  }
  $checks += [ordered]@{ name = "python_tests"; status = $(if ($testExit -eq 0) { "ok" } else { "failed" }); detail = (($testOutput | Select-Object -Last 20) -join "`n") }
  if ($testExit -ne 0) {
    return [ordered]@{ status = "failed"; summary = "Les tests du projet echouent : le code ne fait pas ce qu'il est cense faire."; checks = $checks }
  }
  return [ordered]@{ status = "ok"; summary = "Le code compile et tous les tests du projet passent."; checks = $checks }
}

function Test-WebappProject {
  param([string]$ProjectPath)
  $checkerScript = Join-Path $PSScriptRoot "headless\check-webapp.js"
  $node = Get-Command "node" -ErrorAction SilentlyContinue
  if ($null -eq $node) {
    return [ordered]@{ status = "not_verified"; summary = "Node.js n'est pas disponible, la verification du navigateur a ete ignoree."; checks = @() }
  }
  if (-not (Test-Path -LiteralPath $checkerScript)) {
    return [ordered]@{ status = "not_verified"; summary = "L'outil de verification navigateur n'est pas installe."; checks = @() }
  }
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $output = & $node.Source $checkerScript $ProjectPath 2>&1
  $ErrorActionPreference = $previousErrorActionPreference
  try {
    $parsed = ($output -join "`n") | ConvertFrom-Json
  } catch {
    return [ordered]@{ status = "not_verified"; summary = "La verification du navigateur n'a pas pu s'executer correctement."; checks = @() }
  }
  return [ordered]@{ status = $parsed.status; summary = $parsed.summary; checks = $parsed.checks }
}

function Get-AutoDetectedType {
  param([string]$ProjectPath)
  $hasHtml = @(Get-ChildItem -LiteralPath $ProjectPath -File -Filter "*.html" -ErrorAction SilentlyContinue).Count -gt 0
  if ($hasHtml) { return "webapp" }
  $hasPy = @(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "*.py" -ErrorAction SilentlyContinue).Count -gt 0
  if ($hasPy) { return "python-app" }
  return "other"
}

$type = $ProjectType
if ([string]::IsNullOrWhiteSpace($type)) {
  $type = Get-AutoDetectedType -ProjectPath $ProjectPath
} elseif ($type -eq "desktop" -or $type -eq "other") {
  $detected = Get-AutoDetectedType -ProjectPath $ProjectPath
  if ($detected -ne "other") { $type = $detected }
}

if ($type -eq "webapp") {
  $result = Test-WebappProject -ProjectPath $ProjectPath
} elseif ($type -like "python*" -or $type -eq "api" -or $type -eq "library") {
  $result = Test-PythonProject -ProjectPath $ProjectPath
} else {
  $result = [ordered]@{ status = "not_verified"; summary = "Ce type de projet ne peut pas encore etre verifie automatiquement."; checks = @() }
}

$result | ConvertTo-Json -Depth 8
if ($result.status -eq "failed") { exit 1 }
exit 0
