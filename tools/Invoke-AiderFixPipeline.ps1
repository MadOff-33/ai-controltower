param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [int]$MaxChars = 30000,
  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\ControlTowerCommon.ps1")

function Read-SimpleYaml {
  param([string]$Path)
  $data = @{}
  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
    if ($line -match "^id:\s*(.*?)\s*$") {
      $value = $Matches[1].Trim()
      if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      $data["id"] = $value.Replace('\"', '"')
    }
  }
  return $data
}

$root = (Split-Path -Parent $PSScriptRoot)
$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$ticket = (Resolve-Path -LiteralPath $TicketPath).ProviderPath
$packScript = Join-Path $root "tools\New-FixContextPack.ps1"
$startScript = Join-Path $root "tools\Start-AiderFix.ps1"
$testScript = Join-Path $root "tools\Test-AiderFix.ps1"
$data = Read-SimpleYaml -Path $ticket
$safeId = (($data["id"]) -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
if ([string]::IsNullOrWhiteSpace($safeId)) { throw "Ticket sans id: $ticket" }

Write-Host "=== Aider fix pipeline ==="
& $packScript -WorkspacePath $workspace -TicketPath $ticket -MaxChars $MaxChars
$pack = Join-Path $workspace ("fix_context_packs\" + $safeId + "_pack.md")

$startArgs = @{
  WorkspacePath = $workspace
  TicketPath = $ticket
  ContextPackPath = $pack
  Model = $Model
  HermesMemoryRoot = $HermesMemoryRoot
}
if (-not $RunAider) { $startArgs["DryRun"] = $true }
& $startScript @startArgs

$validation = "skipped"
if ($RunAider -or $ValidateAfterDryRun) {
  & $testScript -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack
  $validation = if ($LASTEXITCODE -eq 0) { "passed" } else { "failed" }
}

$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null
Write-Utf8NoBom -Path (Join-Path $validationDir ($safeId + "_pipeline_result.json")) -Content ([ordered]@{
  completed_at = (Get-Date).ToString("o")
  workspace = $workspace
  ticket = $ticket
  context_pack = $pack
  mode = $(if ($RunAider) { "RunAider" } else { "DryRun" })
  validation = $validation
} | ConvertTo-Json -Depth 6)

Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File `"" + (Join-Path (Split-Path -Parent $PSScriptRoot) "tools\Test-AiderFix.ps1") + "`" -WorkspacePath `"$workspace`" -TicketPath `"$ticket`" -ContextPackPath `"$pack`"")
