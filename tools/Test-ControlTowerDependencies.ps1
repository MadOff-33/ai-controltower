param(
  [string]$ProjectPath = "C:\AI_ControlTower",
  [string]$HermesMemoryRoot = "C:\AI_ControlTower\hermes_memory"
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
  hermes = [ordered]@{
    name = "Hermes central memory"
    available = ((Test-Path -LiteralPath $hermesEntries) -and (Test-Path -LiteralPath $hermesGuidance))
    memory_root = $HermesMemoryRoot
    entries = $hermesEntries
    guidance = $hermesGuidance
  }
}

$result | ConvertTo-Json -Depth 8
