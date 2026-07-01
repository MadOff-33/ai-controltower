param()

$ErrorActionPreference = "Stop"

$Root = "C:\AI_ControlTower"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-PathExists {
  param([string]$Path)
  Assert-True -Condition (Test-Path -LiteralPath $Path) -Message "Missing path: $Path"
}

Write-Host "=== Test ControlTower Flask UI ==="

$required = @(
  "docs\controltower_ui_spec.md",
  "tools\Get-ProjectGitInfo.ps1",
  "tools\Test-ControlTowerDependencies.ps1",
  "tools\New-AiderFixTicketFromReport.ps1",
  "tools\Test-ControlTowerFinalRecipe.ps1",
  "tools\Build-ControlTowerLauncher.ps1",
  "launchers\ControlTowerLauncher.cs",
  "ControlTower.cmd",
  "apps\controltower-ui\app.py",
  "apps\controltower-ui\ControlTower.cmd",
  "apps\controltower-ui\requirements.txt",
  "apps\controltower-ui\README.md",
  "apps\controltower-ui\state.example.json",
  "apps\controltower-ui\templates\index.html",
  "apps\controltower-ui\static\app.js",
  "apps\controltower-ui\static\styles.css"
)

foreach ($relative in $required) {
  Assert-PathExists -Path (Join-Path $Root $relative)
}

$files = @()
$files += Get-ChildItem -LiteralPath (Join-Path $Root "apps\controltower-ui") -Recurse -File
$files += Get-ChildItem -LiteralPath (Join-Path $Root "tools") -File -Filter "*ProjectGitInfo.ps1"
$files += Get-ChildItem -LiteralPath (Join-Path $Root "tools") -File -Filter "*Dependencies.ps1"
$files += Get-ChildItem -LiteralPath (Join-Path $Root "docs") -File -Filter "controltower_ui_spec.md"

foreach ($file in $files) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  Assert-True -Condition (-not $hasBom) -Message ("UTF-8 BOM detected: " + $file.FullName)
}

foreach ($script in @("tools\Get-ProjectGitInfo.ps1", "tools\Test-ControlTowerDependencies.ps1")) {
  $path = Join-Path $Root $script
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  Assert-True -Condition ($errors.Count -eq 0) -Message ("PowerShell parse errors in " + $path)
}

$appPath = Join-Path $Root "apps\controltower-ui\app.py"
$appText = Get-Content -LiteralPath $appPath -Raw
Assert-True -Condition ($appText.Contains("Flask(")) -Message "Flask app factory missing."
Assert-True -Condition ($appText.Contains("@app.route(""/api/state""")) -Message "State API route missing."
Assert-True -Condition ($appText.Contains("@app.route(""/api/run""")) -Message "Run API route missing."
Assert-True -Condition ($appText.Contains("@app.route(""/api/jobs""")) -Message "Jobs API route missing."
Assert-True -Condition ($appText.Contains("@app.route(""/api/jobs/<job_id>""")) -Message "Job detail API route missing."
Assert-True -Condition ($appText.Contains("@app.route(""/api/tickets/from-report""")) -Message "Ticket-from-report API route missing."
Assert-True -Condition ($appText.Contains("WORKFLOW_STEPS")) -Message "Guided workflow missing."
Assert-True -Condition ($appText.Contains("ALLOWED_COMMANDS")) -Message "Command allowlist missing."

$styleText = Get-Content -LiteralPath (Join-Path $Root "apps\controltower-ui\static\styles.css") -Raw
Assert-True -Condition ($styleText.Contains("minmax(560px, 1.65fr)")) -Message "Chat column should be wider than command catalog."
Assert-True -Condition ($styleText.Contains(".command-card button")) -Message "Command buttons should have compact styling."
Assert-True -Condition ($styleText.Contains("min-height: 560px")) -Message "Chat log should have a larger minimum height."

$python = Get-Command py -ErrorAction SilentlyContinue
$pythonArgs = @("-3")
if ($null -eq $python) {
  $python = Get-Command python -ErrorAction SilentlyContinue
  $pythonArgs = @()
}
Assert-True -Condition ($null -ne $python) -Message "Python is required for Flask UI tests."
$compileOutput = & $python.Source @pythonArgs -m py_compile $appPath 2>&1
Assert-True -Condition ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -Message ("Flask app Python syntax check failed. " + ($compileOutput -join "`n"))

$gitInfoJson = & (Join-Path $Root "tools\Get-ProjectGitInfo.ps1") -ProjectPath $Root
$gitInfo = $gitInfoJson | ConvertFrom-Json
Assert-True -Condition ($gitInfo.is_git_repo -eq $true) -Message "Current project should be detected as git repo."
Assert-True -Condition ($gitInfo.github_url -eq "https://github.com/MadOff-33/ai-controltower") -Message ("Unexpected GitHub URL: " + $gitInfo.github_url)

$depsJson = & (Join-Path $Root "tools\Test-ControlTowerDependencies.ps1") -ProjectPath $Root -HermesMemoryRoot (Join-Path $Root "hermes_memory")
$deps = $depsJson | ConvertFrom-Json
Assert-True -Condition ($deps.git.available -eq $true) -Message "Git should be available."
Assert-True -Condition ($deps.hermes.available -eq $true) -Message "Hermes should be initialized."

$selfTestJson = & $python.Source @pythonArgs $appPath --self-test --project-path $Root
Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Flask UI self-test failed."
$selfTest = $selfTestJson | ConvertFrom-Json
Assert-True -Condition ($selfTest.kind -eq "controltower-flask-ui") -Message "Unexpected self-test kind."
Assert-True -Condition ($selfTest.jobs_supported -eq $true) -Message "UI selftest should expose job support."
Assert-True -Condition ($selfTest.workflow_steps.Count -ge 8) -Message "Workflow should expose at least 8 steps."
Assert-True -Condition ($selfTest.commands.audit_dry_run.command.Contains("Invoke-ControlTowerRun.ps1")) -Message "Audit command not generated."
Assert-True -Condition ($selfTest.commands.audit_dry_run.command.Contains("-ValidateAfterDryRun")) -Message "Audit dry-run should validate."
Assert-True -Condition ($selfTest.commands.audit_real.dangerous -eq $true) -Message "Real audit should be marked dangerous."
Assert-True -Condition ($selfTest.commands.fix_dry_run.command.Contains("-Mode Fix")) -Message "Fix dry-run command missing."
Assert-True -Condition ($selfTest.commands.aider_manual.command.Contains("ollama_chat/ornith:9b")) -Message "Manual Aider command missing Ornith."
Assert-True -Condition ($selfTest.github_url -eq "https://github.com/MadOff-33/ai-controltower") -Message "UI selftest did not expose GitHub URL."

$recipeScript = Join-Path $Root "tools\Test-ControlTowerFinalRecipe.ps1"
$recipeText = Get-Content -LiteralPath $recipeScript -Raw
Assert-True -Condition ($recipeText.Contains("Invoke-ControlTowerTestSuite.ps1")) -Message "Final recipe should run the global test suite."
Assert-True -Condition ($recipeText.Contains("Invoke-ControlTowerRun.ps1")) -Message "Final recipe should exercise ControlTower run."

$launcherBuild = Join-Path $Root "tools\Build-ControlTowerLauncher.ps1"
$launcherText = Get-Content -LiteralPath $launcherBuild -Raw
Assert-True -Condition ($launcherText.Contains("ControlTower.exe")) -Message "Launcher builder should produce ControlTower.exe."

Write-Host "All ControlTower Flask UI tests passed."
