param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$MemoryRoot = Join-Path $Root "hermes_lab\hermes memory test"
$Scripts = @(
  "tools\Initialize-HermesMemory.ps1",
  "tools\Add-HermesMemoryEntry.ps1",
  "tools\Update-HermesFromRun.ps1",
  "tools\Get-HermesGuidance.ps1"
)
$DeliveredFiles = @(
  "docs\hermes_central_memory_spec.md",
  "templates\hermes\central_memory.schema.json",
  "tools\tests\Test-HermesMemory.ps1"
) + $Scripts

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

function Remove-TestTree {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $base = [System.IO.Path]::GetFullPath((Join-Path $Root "hermes_lab")).TrimEnd("\")
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  Assert-True -Condition $full.StartsWith($base + "\", [System.StringComparison]::OrdinalIgnoreCase) -Message "Unsafe cleanup path: $full"
  Remove-Item -LiteralPath $full -Recurse -Force
}

Write-Host "=== Test Hermes Central Memory ==="

foreach ($relative in $DeliveredFiles) {
  $path = Join-Path $Root $relative
  Assert-PathExists -Path $path
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $path)
}

foreach ($relative in $Scripts) {
  $path = Join-Path $Root $relative
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

Remove-TestTree -Path $MemoryRoot

& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $MemoryRoot | Out-Null
$central = Join-Path $MemoryRoot "central"
$entries = Join-Path $central "entries.jsonl"
$index = Join-Path $central "index.json"
$guidance = Join-Path $central "guidance_cache.md"
Assert-PathExists -Path $entries
Assert-PathExists -Path $index
Assert-PathExists -Path $guidance
Assert-PathExists -Path (Join-Path $central "schema.json")

& (Join-Path $Root "tools\Add-HermesMemoryEntry.ps1") `
  -MemoryRoot $MemoryRoot `
  -Kind "signal_faible_inedit" `
  -Category "windows_paths" `
  -Summary "Les chemins avec espaces doivent rester cites avec guillemets dans les commandes affichees." `
  -Source "manual_test" `
  -Confidence "medium" `
  -Status "active" `
  -Evidence @("Les pipelines utilisent Quote-Arg.") `
  -Lesson "Toujours afficher la prochaine commande avec chemins guillemetes." `
  -Tags @("paths", "powershell") | Out-Null

$lines = @(Get-Content -LiteralPath $entries)
Assert-True -Condition ($lines.Count -eq 1) -Message "Expected one memory entry after manual add."
$entry = $lines[0] | ConvertFrom-Json
Assert-True -Condition ($entry.kind -eq "signal_faible_inedit") -Message "Open kind was not preserved."
Assert-True -Condition ($entry.category -eq "windows_paths") -Message "Category was not preserved."

$runResult = Join-Path $MemoryRoot "sample_failed_run.json"
$failedRun = [ordered]@{
  mode = "Fix"
  status = "failed"
  data = [ordered]@{ workspace_path = "sample"; ticket_path = "sample_ticket" }
  unauthorized_changes = @([ordered]@{ path = "README.md"; change = "modified" })
  ghost_findings = @([ordered]@{ path = "pkg/core.py"; marker = "main()" })
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($runResult, ($failedRun | ConvertTo-Json -Depth 8), $utf8)

& (Join-Path $Root "tools\Update-HermesFromRun.ps1") -MemoryRoot $MemoryRoot -RunResultPath $runResult | Out-Null
$lines = @(Get-Content -LiteralPath $entries)
Assert-True -Condition ($lines.Count -ge 3) -Message "Expected Hermes to learn from failed run."

& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $MemoryRoot -MaxItems 5 | Out-Null
$guidanceText = Get-Content -LiteralPath $guidance -Raw
Assert-True -Condition ($guidanceText.Contains("Hermes central guidance")) -Message "Guidance header missing."
Assert-True -Condition ($guidanceText.Contains("chemins avec espaces") -or $guidanceText.Contains("fichiers hors ticket") -or $guidanceText.Contains("main()")) -Message "Expected useful guidance content."

Remove-TestTree -Path $MemoryRoot
Write-Host "All Hermes central memory tests passed."
