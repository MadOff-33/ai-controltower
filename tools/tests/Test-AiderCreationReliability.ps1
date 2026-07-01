param()

$ErrorActionPreference = "Stop"
$Root = "C:\AI_ControlTower"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

Write-Host "=== Test Aider Creation Reliability ==="

$lab = Join-Path $Root "hermes_lab\creation test runs"
if (Test-Path -LiteralPath $lab) { Remove-Item -LiteralPath $lab -Recurse -Force }
New-Item -ItemType Directory -Path $lab -Force | Out-Null
$parent = Join-Path $lab "Parent With Spaces"
$workspaces = Join-Path $lab "Creation Workspaces"
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$briefPath = Join-Path $lab "long_brief.md"
$briefText = @"
Creer une petite CLI Python qui additionne deux nombres.

La deuxieme ligne doit rester presente dans le brief final.
Ajouter un README et un test simple.
"@
[System.IO.File]::WriteAllText($briefPath, $briefText, (New-Object System.Text.UTF8Encoding($false)))

$scripts = @(
  "tools\New-CreationWorkspace.ps1",
  "tools\Start-AiderCreation.ps1",
  "tools\Test-AiderCreation.ps1",
  "tools\Invoke-AiderCreationPipeline.ps1",
  "prompts\creation\new_project.md"
)
foreach ($relative in $scripts) {
  $path = Join-Path $Root $relative
  Assert-True -Condition (Test-Path -LiteralPath $path) -Message ("Missing: " + $path)
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $path)
}

foreach ($relative in @("tools\New-CreationWorkspace.ps1", "tools\Start-AiderCreation.ps1", "tools\Test-AiderCreation.ps1", "tools\Invoke-AiderCreationPipeline.ps1")) {
  $path = Join-Path $Root $relative
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

& (Join-Path $Root "tools\Invoke-AiderCreationPipeline.ps1") `
  -ProjectName "Demo Creation" `
  -ParentPath $parent `
  -BriefPath $briefPath `
  -Brief "Créer une petite CLI Python qui additionne deux nombres avec un README et un test simple." `
  -ProjectType "python-cli" `
  -WorkspaceRoot $workspaces `
  -ValidateAfterDryRun
Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Creation dry-run pipeline failed."

$workspace = Get-ChildItem -LiteralPath $workspaces -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Assert-True -Condition ($null -ne $workspace) -Message "Creation workspace not created."
$config = Get-Content -LiteralPath (Join-Path $workspace.FullName "creation.config.json") -Raw | ConvertFrom-Json
$finalBrief = Get-Content -LiteralPath $config.brief_path -Raw
Assert-True -Condition ($finalBrief.Contains("La deuxieme ligne doit rester presente")) -Message "Creation brief should preserve multiline content passed through BriefPath."
Assert-True -Condition (Test-Path -LiteralPath $config.target_project_path) -Message "Target project not created."
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $config.target_project_path "README.md")) -Message "README seed missing."
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $config.target_project_path "pyproject.toml")) -Message "Python pyproject seed missing."
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $config.target_project_path "src\app.py")) -Message "Python app seed missing."
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $config.target_project_path "tests\test_app.py")) -Message "Python test seed missing."
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $workspace.FullName "validation\creation_result.json")) -Message "Creation validation result missing."
$result = Get-Content -LiteralPath (Join-Path $workspace.FullName "validation\creation_result.json") -Raw | ConvertFrom-Json
Assert-True -Condition ($result.passed -eq $true) -Message "Dry-run creation validation should pass on seeded README."

& (Join-Path $Root "tools\Test-AiderCreation.ps1") -WorkspacePath $workspace.FullName -RequireUsefulChanges
Assert-True -Condition ($LASTEXITCODE -ne 0) -Message "Real creation validation should fail when no useful project file changed."

$forbiddenFile = Join-Path $config.target_project_path ".env"
Set-Content -LiteralPath $forbiddenFile -Value "SECRET=bad"
& (Join-Path $Root "tools\Test-AiderCreation.ps1") -WorkspacePath $workspace.FullName
Assert-True -Condition ($LASTEXITCODE -ne 0) -Message "Creation validation should fail on forbidden .env."
Remove-Item -LiteralPath $forbiddenFile -Force

$aiderHistory = Join-Path $config.target_project_path ".aider.chat.history.md"
Set-Content -LiteralPath $aiderHistory -Value "history"
& (Join-Path $Root "tools\Test-AiderCreation.ps1") -WorkspacePath $workspace.FullName
Assert-True -Condition ($LASTEXITCODE -ne 0) -Message "Creation validation should fail on .aider history files inside the target project."
Remove-Item -LiteralPath $aiderHistory -Force

$invalidFailed = $false
try {
  & (Join-Path $Root "tools\New-CreationWorkspace.ps1") -ProjectName "..\bad" -ParentPath $parent -Brief "bad" -WorkspaceRoot $workspaces
} catch {
  $invalidFailed = $true
}
Assert-True -Condition $invalidFailed -Message "Invalid project name should fail."

Write-Host "All Aider creation reliability tests passed."
