param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [int]$MaxChars = 30000,
  [string]$Model = "ollama_chat/ornith:9b",
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Read-SimpleYaml {
  param([string]$Path)
  $data = @{}
  foreach ($line in (Get-Content -LiteralPath $Path)) {
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

$root = "C:\AI_ControlTower"
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
}
if (-not $RunAider) { $startArgs["DryRun"] = $true }
& $startScript @startArgs

$validation = "skipped"
if ($RunAider -or $ValidateAfterDryRun) {
  & $testScript -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack
  $validation = "passed"
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
Write-Host ("powershell -ExecutionPolicy Bypass -File `"C:\AI_ControlTower\tools\Test-AiderFix.ps1`" -WorkspacePath `"$workspace`" -TicketPath `"$ticket`" -ContextPackPath `"$pack`"")
