param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"
$RequiredScripts = @(
  "tools\New-AuditWorkspace.ps1",
  "tools\New-ProjectInventory.ps1",
  "tools\New-AiderFixTicket.ps1",
  "tools\New-FixContextPack.ps1",
  "tools\Start-AiderFix.ps1",
  "tools\Test-AiderFix.ps1",
  "tools\Invoke-AiderFixPipeline.ps1"
)
$DeliveredFiles = @(
  "docs\aider_fix_reliability_spec.md",
  "templates\fix_ticket.yaml"
) + $RequiredScripts

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

function Assert-PathNotExists {
  param([string]$Path)
  Assert-True -Condition (-not (Test-Path -LiteralPath $Path)) -Message "Unexpected path exists: $Path"
}

function Invoke-ExpectFailure {
  param([scriptblock]$Command, [string]$Name)
  $failed = $false
  $global:LASTEXITCODE = 0
  try {
    & $Command
    if ($LASTEXITCODE -ne 0) {
      $failed = $true
      $global:LASTEXITCODE = 0
    }
  } catch {
    $failed = $true
    $global:LASTEXITCODE = 0
  }
  Assert-True -Condition $failed -Message "Expected failure did not happen: $Name"
}

function Remove-TestTree {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $base = [System.IO.Path]::GetFullPath((Join-Path $Root "hermes_lab")).TrimEnd("\")
  $full = [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
  Assert-True -Condition $full.StartsWith($base + "\", [System.StringComparison]::OrdinalIgnoreCase) -Message "Unsafe cleanup path: $full"
  Remove-Item -LiteralPath $full -Recurse -Force
}

function Get-LatestWorkspace {
  param([string]$WorkspaceRoot)
  return (Get-ChildItem -LiteralPath $WorkspaceRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

Write-Host "=== Test Aider Fix Reliability ==="

foreach ($relative in $RequiredScripts) {
  $path = Join-Path $Root $relative
  Assert-PathExists -Path $path
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

foreach ($relative in $DeliveredFiles) {
  $path = Join-Path $Root $relative
  Assert-PathExists -Path $path
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $path)
}

$testRoot = Join-Path $Root "hermes_lab\fix reliability test runs"
$project = Join-Path $testRoot "Project With Spaces"
$workspaceRoot = Join-Path $testRoot "Audit Workspaces"
Remove-TestTree -Path $testRoot
New-Item -ItemType Directory -Path (Join-Path $project "pkg") -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $project "pkg\core.py"), "def add(a, b):`n    return a - b`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $project "README.md"), "# Fixture`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path $project ".env"), "TOKEN=do-not-copy`n", $utf8)

& (Join-Path $Root "tools\New-AuditWorkspace.ps1") -ProjectPath $project -WorkspaceRoot $workspaceRoot -AuditName "Fix Fixture" | Out-Null
$workspace = Get-LatestWorkspace -WorkspaceRoot $workspaceRoot
& (Join-Path $Root "tools\New-ProjectInventory.ps1") -WorkspacePath $workspace | Out-Null

& (Join-Path $Root "tools\New-AiderFixTicket.ps1") `
  -WorkspacePath $workspace `
  -TicketId "fix_add" `
  -Title "Fix add implementation" `
  -Goal "Change pkg/core.py so add returns a + b." `
  -EditableFiles @("pkg/core.py") `
  -ReadonlyFiles @("README.md") `
  -VerificationCommands @("python -c ""from pkg.core import add; assert add(2, 3) == 5""") `
  -AcceptanceCriteria @("pkg/core.py uses addition for add.") | Out-Null

$ticket = Join-Path $workspace "fix_tickets\fix_add.yaml"
Assert-PathExists -Path $ticket

& (Join-Path $Root "tools\New-FixContextPack.ps1") -WorkspacePath $workspace -TicketPath $ticket -MaxChars 12000 | Out-Null
$pack = Join-Path $workspace "fix_context_packs\fix_add_pack.md"
Assert-PathExists -Path $pack

& (Join-Path $Root "tools\Start-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack -DryRun | Out-Null
$fixMessagePath = Join-Path $workspace "fix_runs\fix_add_aider_message.md"
Assert-PathExists -Path $fixMessagePath
Assert-PathExists -Path (Join-Path $workspace "validation\fix_add_baseline.json")
$fixMessage = Get-Content -LiteralPath $fixMessagePath -Raw -Encoding UTF8
Assert-True -Condition ($fixMessage.Contains("ControlTower Aider guidance")) -Message "Fix message should include shared ControlTower guidance."
Assert-True -Condition ($fixMessage.Contains("Hermes central guidance")) -Message "Fix message should include Hermes guidance."
$startFixText = Get-Content -LiteralPath (Join-Path $Root "tools\Start-AiderFix.ps1") -Raw
Assert-True -Condition ($startFixText.Contains("PYTHONUTF8")) -Message "Aider fix must force Python UTF-8 mode on Windows."
Assert-True -Condition ($startFixText.Contains("PYTHONIOENCODING")) -Message "Aider fix must force UTF-8 stdout/stderr on Windows."

$editable = Join-Path $workspace "source_snapshot\pkg\core.py"
[System.IO.File]::WriteAllText($editable, "def add(a, b):`n    return a + b`n", $utf8)
& (Join-Path $Root "tools\Test-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack | Out-Null
Assert-PathExists -Path (Join-Path $workspace "validation\fix_add_result.json")

& (Join-Path $Root "tools\Start-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack -DryRun | Out-Null
[System.IO.File]::WriteAllText((Join-Path $workspace "source_snapshot\README.md"), "# Changed illegally`n", $utf8)
Invoke-ExpectFailure -Name "readonly file modified" -Command {
  & (Join-Path $Root "tools\Test-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack
}

& (Join-Path $Root "tools\Start-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack -DryRun | Out-Null
[System.IO.File]::WriteAllText((Join-Path $workspace "source_snapshot\pkg\ghost.py"), "def main():`n    pass`n", $utf8)
Invoke-ExpectFailure -Name "unauthorized new file" -Command {
  & (Join-Path $Root "tools\Test-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack
}

Invoke-ExpectFailure -Name "absolute editable path rejected" -Command {
  & (Join-Path $Root "tools\New-AiderFixTicket.ps1") -WorkspacePath $workspace -TicketId "bad_abs" -Title "Bad" -Goal "Bad" -EditableFiles @("C:\temp\bad.py")
}

Remove-TestTree -Path $testRoot
Write-Host "All Aider fix reliability tests passed."
