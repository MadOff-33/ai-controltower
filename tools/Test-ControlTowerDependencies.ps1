param(
  [string]$ProjectPath = (Split-Path -Parent $PSScriptRoot),
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory")
)

$ErrorActionPreference = "Stop"

function Test-CommandAvailable {
  param([string]$Name)
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  return [ordered]@{
    name = $Name
    available = ($null -ne $command)
    path = $(if ($null -ne $command) { [string]$command.Source } else { "" })
  }
}

function Test-OllamaModel {
  param([string]$ModelName)
  $available = $false
  if (Get-Command "ollama" -ErrorAction SilentlyContinue) {
    try {
      $models = @(& ollama list 2>$null)
      $available = (($models -join "`n") -match [regex]::Escape($ModelName))
    } catch {
      $available = $false
    }
  }
  return [ordered]@{ name = $ModelName; available = $available }
}

function Test-OllamaServingHealth {
  param([string]$ModelName)
  $status = "unknown"
  $message = ""
  if (Get-Command "ollama" -ErrorAction SilentlyContinue) {
    try {
      $modelfileLines = @(& ollama show $ModelName --modelfile 2>$null)
      $modelfile = $modelfileLines -join "`n"
      $hasRenderer = $modelfile -match "(?m)^RENDERER\s+\S"
      $hasRawTemplate = $modelfile -match '(?m)^TEMPLATE\s+\{\{\s*\.Prompt\s*\}\}\s*$'
      if ($hasRawTemplate -and -not $hasRenderer) {
        $status = "warning"
        $message = "Modele '" + $ModelName + "': template Ollama en passthrough brut ({{ .Prompt }}) sans RENDERER declare. Le modele risque de ne pas recevoir son format de conversation attendu."
      } elseif ([string]::IsNullOrWhiteSpace($modelfile)) {
        $status = "unknown"
        $message = "Modele '" + $ModelName + "' introuvable via 'ollama show'."
      } else {
        $status = "ok"
        $message = "Modele '" + $ModelName + "': template/renderer Ollama presents."
      }
    } catch {
      $status = "unknown"
      $message = "Impossible de verifier le modelfile Ollama pour '" + $ModelName + "': " + $_.Exception.Message
    }
  } else {
    $status = "unknown"
    $message = "Ollama introuvable, verification de service ignoree."
  }
  return [ordered]@{ name = $ModelName; status = $status; message = $message }
}

function Test-HeadlessBrowser {
  param([string]$ScriptRoot)
  $nodeAvailable = $null -ne (Get-Command "node" -ErrorAction SilentlyContinue)
  $playwrightPath = Join-Path $ScriptRoot "headless\node_modules\playwright"
  $playwrightAvailable = $nodeAvailable -and (Test-Path -LiteralPath $playwrightPath)
  return [ordered]@{ name = "Playwright"; available = $playwrightAvailable }
}

$projectExists = Test-Path -LiteralPath $ProjectPath
$hermesEntries = Join-Path $HermesMemoryRoot "central\entries.jsonl"
$hermesGuidance = Join-Path $HermesMemoryRoot "central\guidance_cache.md"

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  project = [ordered]@{
    path = $ProjectPath
    available = $projectExists
  }
  powershell = [ordered]@{
    name = "powershell"
    available = $true
    version = $PSVersionTable.PSVersion.ToString()
  }
  git = Test-CommandAvailable -Name "git"
  aider = Test-CommandAvailable -Name "aider"
  ollama = Test-CommandAvailable -Name "ollama"
  ornith = Test-OllamaModel -ModelName "ornith:9b"
  serving_health = Test-OllamaServingHealth -ModelName "ornith:9b"
  headless_browser = Test-HeadlessBrowser -ScriptRoot $PSScriptRoot
  hermes = [ordered]@{
    name = "Hermes central memory"
    available = ((Test-Path -LiteralPath $hermesEntries) -and (Test-Path -LiteralPath $hermesGuidance))
    memory_root = $HermesMemoryRoot
    entries = $hermesEntries
    guidance = $hermesGuidance
  }
}

$result | ConvertTo-Json -Depth 8
