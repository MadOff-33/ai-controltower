# Auto-Correction Loop & Hermes Reinforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a Creation/Fix run fails its functional check, automatically retry Aider with a single-file, single-defect targeted brief (up to 5 attempts) instead of leaving the user to manually correct it, while recording a quantitative per-check-type success rate in Hermes memory that feeds back into future Aider guidance — plus a screenshot on browser crashes, surfaced in the existing UI.

**Architecture:** A new standalone script (`tools/Invoke-AutoCorrectionLoop.ps1`) is called directly from `Test-AiderCreation.ps1`/`Test-AiderFix.ps1` right after their existing `functional_check` computation, replacing a `"failed"` result with either a resolved one or an exhausted one — no new propagation chain is needed, it reuses the exact `functional_check` → run log → `/api/state` → UI chain Sub-project 1 already built. `check-webapp.js` gains two always-present fields (`html_file`, `script_files`) the loop uses for file targeting, plus screenshot capture on browser crashes. `Get-HermesGuidance.ps1` gains an aggregated success-rate summary computed from `correction_attempt` entries.

**Tech Stack:** PowerShell 5.1/7, Node.js + Playwright (already installed by sub-project 1), vanilla JS/CSS.

## Global Constraints

- Audit mode is not covered — same as sub-project 1, this only applies where Creation/Fix already run the functional check.
- No new dependency — reuses Playwright already installed by sub-project 1.
- 5 attempts maximum (`-MaxAttempts` parameter, default 5, overridable).
- One file per correction pass, except `python_tests` failures (no reliable single-file signal — all non-test Python source files are given to Aider for that one case).
- Every correction brief must be generic — built from a template keyed by check name plus the check's own `detail` field, never hardcoded to a specific project.
- Hermes weighting must be quantitative (counted successes/failures per check-type), not just qualitative free-text lessons.
- Test commands: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` (PowerShell suites) and `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` (Flask UI) from the worktree root.
- This branch stacks on sub-project 1's unmerged branch (`worktree-functional-verification-engine`) — all file line numbers below assume that branch's current state, not `main`.

---

### Task 1: Extend `check-webapp.js` with file-targeting fields and screenshot capture

**Files:**
- Modify: `tools/headless/check-webapp.js`

**Interfaces:**
- Produces: the script's JSON output gains two fields, always present regardless of pass/fail: `html_file` (the HTML file's basename, e.g. `"index.html"`) and `script_files` (array of the `<script src="...">` paths found, e.g. `["app.js"]`). It also gains `screenshot_path` (absolute path to a saved PNG, only present when the `browser_console` check failed — `null`/absent otherwise). These are consumed by Task 2 (file targeting) and Task 5 (UI display).

- [ ] **Step 1: Add `html_file`/`script_files` to every return path and capture a screenshot on browser failure**

In `tools/headless/check-webapp.js`, change:

old:
```javascript
  const html = fs.readFileSync(htmlPath, 'utf8');
  const htmlIds = new Set([...html.matchAll(/\bid=["']([^"']+)["']/g)].map((m) => m[1]));
  const htmlClasses = new Set();
  for (const m of html.matchAll(/\bclass=["']([^"']+)["']/g)) {
    for (const cls of m[1].split(/\s+/)) {
      if (cls) htmlClasses.add(cls);
    }
  }

  const scriptFiles = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/g)].map((m) => m[1]);
  const missingRefs = [];
```

new:
```javascript
  const html = fs.readFileSync(htmlPath, 'utf8');
  const htmlFileName = path.basename(htmlPath);
  const htmlIds = new Set([...html.matchAll(/\bid=["']([^"']+)["']/g)].map((m) => m[1]));
  const htmlClasses = new Set();
  for (const m of html.matchAll(/\bclass=["']([^"']+)["']/g)) {
    for (const cls of m[1].split(/\s+/)) {
      if (cls) htmlClasses.add(cls);
    }
  }

  const scriptFiles = [...html.matchAll(/<script[^>]+src=["']([^"']+)["']/g)].map((m) => m[1]);
  const missingRefs = [];
```

Then change the missing-references early return:

old:
```javascript
  if (missingRefs.length > 0) {
    const first = missingRefs[0];
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le code cherche un element "${first.name}" qui n'existe pas dans la page (${first.file}).`,
      checks
    }));
    return;
  }
```

new:
```javascript
  if (missingRefs.length > 0) {
    const first = missingRefs[0];
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le code cherche un element "${first.name}" qui n'existe pas dans la page (${first.file}).`,
      checks,
      html_file: htmlFileName,
      script_files: scriptFiles
    }));
    return;
  }
```

Then change the Playwright-missing fallback:

old:
```javascript
  let playwright;
  try {
    playwright = require('playwright');
  } catch (err) {
    checks.push({ name: 'browser_console', status: 'not_verified', detail: 'Playwright non installe.' });
    console.log(JSON.stringify({
      status: 'ok',
      summary: "Recoupement HTML/JS reussi. Le chargement dans un navigateur n'a pas pu etre verifie (Playwright non installe).",
      checks
    }));
    return;
  }

  const consoleErrors = [];
  const browser = await playwright.chromium.launch();
  try {
    const page = await browser.newPage();
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => {
      consoleErrors.push(err.message);
    });
    await page.goto(require('url').pathToFileURL(htmlPath).href);
    await page.waitForTimeout(3000);
  } finally {
    await browser.close();
  }

  checks.push({
    name: 'browser_console',
    status: consoleErrors.length === 0 ? 'ok' : 'failed',
    detail: consoleErrors.join(' | ')
  });

  if (consoleErrors.length > 0) {
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le site plante des l'ouverture : ${consoleErrors[0]}`,
      checks
    }));
    return;
  }

  console.log(JSON.stringify({ status: 'ok', summary: 'La page se charge correctement, sans erreur.', checks }));
```

new:
```javascript
  let playwright;
  try {
    playwright = require('playwright');
  } catch (err) {
    checks.push({ name: 'browser_console', status: 'not_verified', detail: 'Playwright non installe.' });
    console.log(JSON.stringify({
      status: 'ok',
      summary: "Recoupement HTML/JS reussi. Le chargement dans un navigateur n'a pas pu etre verifie (Playwright non installe).",
      checks,
      html_file: htmlFileName,
      script_files: scriptFiles
    }));
    return;
  }

  const consoleErrors = [];
  let screenshotPath = null;
  const browser = await playwright.chromium.launch();
  try {
    const page = await browser.newPage();
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('pageerror', (err) => {
      consoleErrors.push(err.message);
    });
    await page.goto(require('url').pathToFileURL(htmlPath).href);
    await page.waitForTimeout(3000);
    if (consoleErrors.length > 0) {
      const validationDir = path.join(projectPath, 'validation');
      if (!fs.existsSync(validationDir)) fs.mkdirSync(validationDir, { recursive: true });
      screenshotPath = path.join(validationDir, 'screenshot.png');
      await page.screenshot({ path: screenshotPath });
    }
  } finally {
    await browser.close();
  }

  checks.push({
    name: 'browser_console',
    status: consoleErrors.length === 0 ? 'ok' : 'failed',
    detail: consoleErrors.join(' | ')
  });

  if (consoleErrors.length > 0) {
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le site plante des l'ouverture : ${consoleErrors[0]}`,
      checks,
      html_file: htmlFileName,
      script_files: scriptFiles,
      screenshot_path: screenshotPath
    }));
    return;
  }

  console.log(JSON.stringify({
    status: 'ok',
    summary: 'La page se charge correctement, sans erreur.',
    checks,
    html_file: htmlFileName,
    script_files: scriptFiles
  }));
```

- [ ] **Step 2: Manually verify against the existing fixtures**

Using the same three fixture patterns from sub-project 1 (a scratch directory with `index.html` + `app.js`):

Fixture A (good, matching ids, no console errors): run `node tools/headless/check-webapp.js <fixture-dir>`. Expected: `"status": "ok"`, `"html_file": "index.html"`, `"script_files": ["app.js"]`, no `screenshot_path` key.

Fixture B (missing DOM id, matching earlier sub-project 1 fixture): expected `"status": "failed"`, `"html_file"` and `"script_files"` still present (the fields must appear even on this early-return path).

Fixture C (console error on load, e.g. `app.js` containing `null.crashHere();` with matching ids so it reaches the browser-launch phase): expected `"status": "failed"`, and `"screenshot_path"` pointing at a real PNG file under `<fixture-dir>/validation/screenshot.png` — confirm the file actually exists on disk and is non-empty.

- [ ] **Step 3: Commit**

```bash
git add tools/headless/check-webapp.js
git commit -m "feat: expose html_file/script_files and capture screenshot on browser crash"
```

---

### Task 2: `tools/Invoke-AutoCorrectionLoop.ps1` — the retry engine

**Files:**
- Create: `tools/Invoke-AutoCorrectionLoop.ps1`
- Create: `tools/tests/Test-AutoCorrectionLoop.ps1`
- Modify: `tools/tests/Invoke-ControlTowerTestSuite.ps1`

**Interfaces:**
- Consumes: `tools/Test-ProjectFunctional.ps1` (from sub-project 1, unmodified except its dependency on Task 1's new `html_file`/`script_files` fields, which it already passes through transparently since it does `$parsed.checks`-style relay — no change needed to `Test-ProjectFunctional.ps1` itself since it forwards the whole parsed object's `status`/`summary`/`checks`; **this task must also make it forward the new fields**, see Step 1's note). `tools/Add-HermesMemoryEntry.ps1` (`-MemoryRoot -Kind -Category -Summary -Source -ContextJson`, all pre-existing, unchanged).
- Produces: `powershell -File tools/Invoke-AutoCorrectionLoop.ps1 -ProjectPath <path> [-ProjectType <type>] -HermesMemoryRoot <path> [-MaxAttempts 5] [-Model "ollama_chat/ornith:9b"] [-AiderExecutable "aider"]` — prints one JSON object to stdout: `{ status, summary, checks, html_file, script_files, screenshot_path, auto_correction: { attempts_used, max_attempts, resolved, history: [{attempt, check_name, target_file, outcome}] } }`. Exit code 0 unless final `status == "failed"`. This is what Task 3 calls in place of a bare `Test-ProjectFunctional.ps1` invocation when the first check comes back `"failed"`.

- [ ] **Step 1: Make `Test-ProjectFunctional.ps1` relay the new fields from `check-webapp.js`**

`Test-WebappProject` in `tools/Test-ProjectFunctional.ps1` currently only relays `status`/`summary`/`checks` from the parsed `check-webapp.js` output, dropping the new `html_file`/`script_files`/`screenshot_path` fields Task 1 added. Change:

old:
```powershell
  try {
    $parsed = ($output -join "`n") | ConvertFrom-Json
  } catch {
    return [ordered]@{ status = "not_verified"; summary = "La verification du navigateur n'a pas pu s'executer correctement."; checks = @() }
  }
  return [ordered]@{ status = $parsed.status; summary = $parsed.summary; checks = $parsed.checks }
```

new:
```powershell
  try {
    $parsed = ($output -join "`n") | ConvertFrom-Json
  } catch {
    return [ordered]@{ status = "not_verified"; summary = "La verification du navigateur n'a pas pu s'executer correctement."; checks = @() }
  }
  return [ordered]@{
    status = $parsed.status
    summary = $parsed.summary
    checks = $parsed.checks
    html_file = $parsed.html_file
    script_files = $parsed.script_files
    screenshot_path = $parsed.screenshot_path
  }
```

- [ ] **Step 2: Write the loop script**

Create `tools/Invoke-AutoCorrectionLoop.ps1`:

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,

  [string]$ProjectType = "",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [string]$Model = "ollama_chat/ornith:9b",
  [int]$MaxAttempts = 5,
  [string]$AiderExecutable = "aider"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "lib\ControlTowerCommon.ps1")

function Get-TargetFileForCheck {
  param([string]$ProjectPath, [pscustomobject]$Check, [pscustomobject]$FunctionalResult)
  if ($Check.name -eq "dom_reference_check") {
    if ($FunctionalResult.html_file) { return Join-Path $ProjectPath $FunctionalResult.html_file }
    return $null
  }
  if ($Check.name -eq "browser_console") {
    if ($FunctionalResult.script_files -and @($FunctionalResult.script_files).Count -gt 0) {
      return Join-Path $ProjectPath (@($FunctionalResult.script_files)[0])
    }
    return $null
  }
  if ($Check.name -eq "python_syntax") {
    $firstPath = ([string]$Check.detail -split ", ")[0]
    if (-not [string]::IsNullOrWhiteSpace($firstPath)) { return $firstPath }
    return $null
  }
  return $null
}

function Build-CorrectionBrief {
  param([pscustomobject]$Check)
  if ($Check.name -eq "dom_reference_check") {
    return "Le fichier JS reference un element HTML manquant : " + $Check.detail + ". Ajoute l'element manquant dans le fichier HTML avec l'id/class exact mentionne, sans rien supprimer d'existant."
  }
  if ($Check.name -eq "browser_console") {
    return "Le site plante au chargement avec cette erreur JavaScript : " + $Check.detail + ". Corrige le bug dans le code JavaScript qui cause cette erreur, sans changer le comportement du reste du code."
  }
  if ($Check.name -eq "python_syntax") {
    return "Le fichier contient une erreur de syntaxe : " + $Check.detail + ". Corrige uniquement l'erreur de syntaxe."
  }
  if ($Check.name -eq "python_tests") {
    return "Les tests echouent avec cette sortie : " + $Check.detail + ". Corrige le code pour que les tests passent, sans modifier les tests eux-memes."
  }
  return "Corrige ce probleme : " + $Check.detail
}

function Invoke-TargetedAiderFix {
  param([string]$ProjectPath, [string]$TargetFile, [string]$BriefText, [string]$Model, [string]$AiderExecutable)
  $messagePath = [System.IO.Path]::GetTempFileName()
  Write-Utf8NoBom -Path $messagePath -Content $BriefText
  try {
    $aiderArgs = @(
      "--model", $Model,
      "--no-git", "--no-gitignore", "--no-auto-commits", "--no-dirty-commits",
      "--no-pretty", "--no-stream", "--no-fancy-input", "--yes-always",
      "--no-restore-chat-history"
    )
    if ($TargetFile -and (Test-Path -LiteralPath $TargetFile)) {
      $aiderArgs += $TargetFile
    } else {
      $pyFiles = @(Get-ChildItem -LiteralPath $ProjectPath -Recurse -File -Filter "*.py" -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\(\.venv|venv|__pycache__|\.git|tests)\\' -and $_.Name -notlike "test_*" -and $_.Name -notlike "*_test.py"
      })
      $aiderArgs += @($pyFiles | ForEach-Object { $_.FullName })
    }
    $aiderArgs += @("--message-file", $messagePath)
    Enable-AiderUtf8Environment
    Push-Location $ProjectPath
    try {
      & $AiderExecutable @aiderArgs 2>&1 | Out-Null
    } finally {
      Pop-Location
      Restore-AiderUtf8Environment
    }
  } finally {
    Remove-Item -LiteralPath $messagePath -Force -ErrorAction SilentlyContinue
  }
}

$functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
$history = @()
$attempt = 0
$result = $null

while ($attempt -lt $MaxAttempts) {
  $output = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $ProjectPath -ProjectType $ProjectType | Out-String
  $result = $output | ConvertFrom-Json
  if ($result.status -ne "failed") { break }

  $failedCheck = @($result.checks | Where-Object { $_.status -eq "failed" }) | Select-Object -First 1
  if ($null -eq $failedCheck) { break }

  $targetFile = Get-TargetFileForCheck -ProjectPath $ProjectPath -Check $failedCheck -FunctionalResult $result
  $brief = Build-CorrectionBrief -Check $failedCheck
  $targetLabel = if ($targetFile) { Split-Path -Leaf $targetFile } else { "plusieurs fichiers" }

  Write-Host ("=== Tentative de correction " + ($attempt + 1) + "/" + $MaxAttempts + " : " + $failedCheck.name + " dans " + $targetLabel + " ===")

  Invoke-TargetedAiderFix -ProjectPath $ProjectPath -TargetFile $targetFile -BriefText $brief -Model $Model -AiderExecutable $AiderExecutable

  $attempt++

  $recheckOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $ProjectPath -ProjectType $ProjectType | Out-String
  $recheckResult = $recheckOutput | ConvertFrom-Json
  $stillFailingSameCheck = @($recheckResult.checks | Where-Object { $_.name -eq $failedCheck.name -and $_.status -eq "failed" }).Count -gt 0
  $outcome = if ($stillFailingSameCheck) { "not_fixed" } else { "fixed" }

  $history += [ordered]@{ attempt = $attempt; check_name = $failedCheck.name; target_file = $targetFile; outcome = $outcome }

  $contextJson = (@{ outcome = $outcome; target_file = $targetFile; attempt_number = $attempt } | ConvertTo-Json -Compress)
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Add-HermesMemoryEntry.ps1") `
    -MemoryRoot $HermesMemoryRoot -Kind "correction_attempt" -Category $failedCheck.name -Source "auto_correction_loop" `
    -Summary ("Tentative de correction automatique sur " + $failedCheck.name + " : " + $outcome) `
    -ContextJson $contextJson | Out-Null

  $result = $recheckResult
}

$resolved = ($result.status -ne "failed")
$summaryPrefix = ""
if ($resolved -and $attempt -gt 0) {
  $summaryPrefix = "Corrige automatiquement apres " + $attempt + " tentative" + $(if ($attempt -gt 1) { "s" } else { "" }) + ". "
} elseif ((-not $resolved) -and $attempt -ge $MaxAttempts) {
  $summaryPrefix = "Echec apres " + $MaxAttempts + " tentatives de correction automatique, correction manuelle necessaire. "
}

$finalResult = [ordered]@{
  status = $result.status
  summary = $summaryPrefix + $result.summary
  checks = $result.checks
  html_file = $result.html_file
  script_files = $result.script_files
  screenshot_path = $result.screenshot_path
  auto_correction = [ordered]@{
    attempts_used = $attempt
    max_attempts = $MaxAttempts
    resolved = $resolved
    history = $history
  }
}

$finalResult | ConvertTo-Json -Depth 10
if ($finalResult.status -eq "failed") { exit 1 }
exit 0
```

- [ ] **Step 3: Write the test suite with a fake Aider stand-in**

Create `tools/tests/Test-AutoCorrectionLoop.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$loopScript = Join-Path $Root "tools\Invoke-AutoCorrectionLoop.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function New-Fixture {
  param([string]$Name)
  $path = Join-Path $Root ("hermes_lab\auto correction fixtures\" + $Name)
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

$hermesFixture = Join-Path $Root "hermes_lab\auto correction fixtures\hermes_memory"
if (Test-Path -LiteralPath $hermesFixture) { Remove-Item -LiteralPath $hermesFixture -Recurse -Force }
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null

Write-Host "=== Test-AutoCorrectionLoop: resolves on first attempt ==="
$fixture = New-Fixture -Name "resolves_first_attempt"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$fakeAider = Join-Path $Root "tools\tests\fixtures\fake-aider-fixes-html.ps1"
$json = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $fixture -ProjectType "webapp" -HermesMemoryRoot $hermesFixture -MaxAttempts 5 -AiderExecutable $fakeAider | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)
Assert-True -Condition ($result.auto_correction.resolved -eq $true) -Message "Expected resolved=true"
Assert-True -Condition ($result.auto_correction.attempts_used -eq 1) -Message ("Expected 1 attempt, got " + $result.auto_correction.attempts_used)
Assert-True -Condition ($result.summary.Contains("Corrige automatiquement apres 1 tentative")) -Message "Summary should mention attempt count"

Write-Host "=== Test-AutoCorrectionLoop: exhausts max attempts on an unfixable defect ==="
$fixture = New-Fixture -Name "exhausts_attempts"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$fakeAiderNoop = Join-Path $Root "tools\tests\fixtures\fake-aider-noop.ps1"
$json = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $fixture -ProjectType "webapp" -HermesMemoryRoot $hermesFixture -MaxAttempts 3 -AiderExecutable $fakeAiderNoop | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)
Assert-True -Condition ($result.auto_correction.resolved -eq $false) -Message "Expected resolved=false"
Assert-True -Condition ($result.auto_correction.attempts_used -eq 3) -Message ("Expected 3 attempts, got " + $result.auto_correction.attempts_used)
Assert-True -Condition ($result.summary.Contains("Echec apres 3 tentatives")) -Message "Summary should mention exhaustion"

Write-Host "=== Test-AutoCorrectionLoop: Get-TargetFileForCheck branches ==="
. $loopScript -ProjectPath (New-Fixture -Name "target_file_probe") -ProjectType "other" -HermesMemoryRoot $hermesFixture -MaxAttempts 0 2>$null | Out-Null
$domCheck = [pscustomobject]@{ name = "dom_reference_check"; status = "failed"; detail = "app.js: reference..." }
$functionalResult = [pscustomobject]@{ html_file = "index.html"; script_files = @("app.js") }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $domCheck -FunctionalResult $functionalResult
Assert-True -Condition ($target -eq (Join-Path "C:\fake\project" "index.html")) -Message ("dom_reference_check should target the HTML file, got " + $target)

$consoleCheck = [pscustomobject]@{ name = "browser_console"; status = "failed"; detail = "TypeError..." }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $consoleCheck -FunctionalResult $functionalResult
Assert-True -Condition ($target -eq (Join-Path "C:\fake\project" "app.js")) -Message ("browser_console should target the first script file, got " + $target)

$syntaxCheck = [pscustomobject]@{ name = "python_syntax"; status = "failed"; detail = "C:\fake\project\main.py" }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $syntaxCheck -FunctionalResult ([pscustomobject]@{})
Assert-True -Condition ($target -eq "C:\fake\project\main.py") -Message ("python_syntax should target the file from detail, got " + $target)

$testsCheck = [pscustomobject]@{ name = "python_tests"; status = "failed"; detail = "1 failed" }
$target = Get-TargetFileForCheck -ProjectPath "C:\fake\project" -Check $testsCheck -FunctionalResult ([pscustomobject]@{})
Assert-True -Condition ($null -eq $target) -Message "python_tests should return no single target file"

Write-Host ""
Write-Host "All Test-AutoCorrectionLoop checks passed."
```

- [ ] **Step 4: Write the two fake Aider fixtures the test suite invokes**

Create `tools/tests/fixtures/fake-aider-fixes-html.ps1` (simulates a correction that actually fixes the DOM-reference bug, regardless of arguments given — for a deterministic "resolves" test case):

```powershell
param()
$fileArg = $args | Where-Object { $_ -like "*.html" } | Select-Object -First 1
if ($fileArg -and (Test-Path -LiteralPath $fileArg)) {
  Set-Content -LiteralPath $fileArg -Value '<html><body><div id="app"></div><script src="app.js"></script></body></html>'
}
exit 0
```

Create `tools/tests/fixtures/fake-aider-noop.ps1` (simulates a correction attempt that never actually fixes anything, to exercise the exhaustion path):

```powershell
param()
exit 0
```

- [ ] **Step 5: Run the new suite directly**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-AutoCorrectionLoop.ps1`

Expected: `All Test-AutoCorrectionLoop checks passed.`, exit code 0.

- [ ] **Step 6: Register the suite**

In `tools/tests/Invoke-ControlTowerTestSuite.ps1`, change:

```powershell
$Suites = @(
  "Test-PowerShellEncodingLint.ps1",
  "Test-ProjectFunctionalCheck.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

to:

```powershell
$Suites = @(
  "Test-PowerShellEncodingLint.ps1",
  "Test-ProjectFunctionalCheck.ps1",
  "Test-AutoCorrectionLoop.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

- [ ] **Step 7: Commit**

```bash
git add tools/Test-ProjectFunctional.ps1 tools/Invoke-AutoCorrectionLoop.ps1 tools/tests/Test-AutoCorrectionLoop.ps1 tools/tests/fixtures/fake-aider-fixes-html.ps1 tools/tests/fixtures/fake-aider-noop.ps1 tools/tests/Invoke-ControlTowerTestSuite.ps1
git commit -m "feat: add auto-correction loop engine with single-file targeting"
```

---

### Task 3: Wire the loop into `Test-AiderCreation.ps1` and `Test-AiderFix.ps1`

**Files:**
- Modify: `tools/Test-AiderCreation.ps1:165-172`
- Modify: `tools/Test-AiderFix.ps1:130-138`

**Interfaces:**
- Consumes: `tools/Invoke-AutoCorrectionLoop.ps1` (Task 2), invoked as `powershell -File <path> -ProjectPath <dir> [-ProjectType <type>] -HermesMemoryRoot <path>`, JSON stdout with `status`/`summary`/`checks`/`auto_correction`/etc.
- Produces: both scripts' `functional_check` (already written into their result JSON since sub-project 1) now reflects the loop's final, possibly-resolved state instead of the first raw failure — no other change to either script's JSON shape or downstream consumers (sub-project 1's whole propagation chain, unmodified, picks this up automatically).

- [ ] **Step 1: Wire the loop into `Test-AiderCreation.ps1`**

In `tools/Test-AiderCreation.ps1`, change:

old:
```powershell
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $target -ProjectType ([string]$config.project_type) | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
  }
```

new:
```powershell
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $target -ProjectType ([string]$config.project_type) | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
    if ($functionalCheck.status -eq "failed") {
      $loopScript = Join-Path $PSScriptRoot "Invoke-AutoCorrectionLoop.ps1"
      if (Test-Path -LiteralPath $loopScript) {
        $hermesRootForLoop = if ($HermesMemoryRoot) { $HermesMemoryRoot } else { Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory" }
        $loopOutput = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $target -ProjectType ([string]$config.project_type) -HermesMemoryRoot $hermesRootForLoop | Out-String
        try {
          $functionalCheck = $loopOutput | ConvertFrom-Json
        } catch {
          # Keep the original failed $functionalCheck if the loop's own output can't be parsed.
        }
      }
    }
  }
```

Note: `Test-AiderCreation.ps1` does not currently declare a `-HermesMemoryRoot` parameter. Add it to the param block. Find:

old:
```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [switch]$RequireUsefulChanges
)
```

new:
```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$RequireUsefulChanges
)
```

(If the actual current param block differs slightly from this — e.g. if a `-HermesMemoryRoot` parameter already exists from earlier work — skip this param-block edit and just reference the existing `$HermesMemoryRoot` variable in Step 1's edit above.)

- [ ] **Step 2: Wire the loop into `Test-AiderFix.ps1`**

`Test-AiderFix.ps1` already declares no `-HermesMemoryRoot` param either per the research; check its current param block the same way as Step 1 and add one if missing, following the identical pattern. Then change:

old:
```powershell
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $snapshot | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
  }
```

new:
```powershell
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $snapshot | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
    if ($functionalCheck.status -eq "failed") {
      $loopScript = Join-Path $PSScriptRoot "Invoke-AutoCorrectionLoop.ps1"
      if (Test-Path -LiteralPath $loopScript) {
        $hermesRootForLoop = if ($HermesMemoryRoot) { $HermesMemoryRoot } else { Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory" }
        $loopOutput = & powershell -ExecutionPolicy Bypass -File $loopScript -ProjectPath $snapshot -HermesMemoryRoot $hermesRootForLoop | Out-String
        try {
          $functionalCheck = $loopOutput | ConvertFrom-Json
        } catch {
          # Keep the original failed $functionalCheck if the loop's own output can't be parsed.
        }
      }
    }
  }
```

Note: `-ProjectType` is intentionally omitted here (Fix mode has no declared type, matching sub-project 1's existing pattern of relying on auto-detection for this script).

- [ ] **Step 3: Verify with the reliability suites**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-AiderCreationReliability.ps1"`

Expected: exit 0. These suites run in dry-run mode (no real Aider), so `functional_check.status` should never actually be `"failed"` from a real bug — this run mainly confirms no syntax error was introduced and the new code path (guarded by `if ($functionalCheck.status -eq "failed")`) is never triggered, hence never calls the loop, hence doesn't need real Aider to pass.

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-AiderFixReliability.ps1"`

Expected: exit 0, same reasoning.

- [ ] **Step 4: Commit**

```bash
git add tools/Test-AiderCreation.ps1 tools/Test-AiderFix.ps1
git commit -m "feat: trigger auto-correction loop on functional check failure"
```

---

### Task 4: Quantitative Hermes reinforcement in `Get-HermesGuidance.ps1`

**Files:**
- Modify: `tools/Get-HermesGuidance.ps1`
- Create: `tools/tests/Test-HermesReinforcementAggregation.ps1`
- Modify: `tools/tests/Invoke-ControlTowerTestSuite.ps1`

**Interfaces:**
- Consumes: `entries.jsonl` entries with `kind = "correction_attempt"` (written by Task 2's loop via `Add-HermesMemoryEntry.ps1`, using the pre-existing `-ContextJson` parameter — no changes needed to `Add-HermesMemoryEntry.ps1`).
- Produces: `guidance_cache.md` gains an extra section (after the existing entry list) summarizing success rate per `category` (check name) — visible to Aider in every future run via the existing `## Hermes memory guidance` inclusion in `Start-Aider*.ps1`'s message construction (unmodified, already wired).

- [ ] **Step 1: Add the aggregation logic**

In `tools/Get-HermesGuidance.ps1`, change:

old:
```powershell
$selected = @($items | Sort-Object created_at -Descending | Select-Object -First $MaxItems)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Hermes central guidance") | Out-Null
$lines.Add("") | Out-Null

if ($selected.Count -eq 0) {
  $lines.Add("Aucune experience centrale active pour le moment.") | Out-Null
} else {
  foreach ($entry in $selected) {
    $text = [string]$entry.summary
    if ($entry.lesson) { $text = $text + " Lesson: " + [string]$entry.lesson }
    $lines.Add("- [" + [string]$entry.kind + "/" + [string]$entry.category + "] " + $text) | Out-Null
  }
}

Write-Utf8NoBom -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
```

new:
```powershell
$selected = @($items | Sort-Object created_at -Descending | Select-Object -First $MaxItems)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Hermes central guidance") | Out-Null
$lines.Add("") | Out-Null

if ($selected.Count -eq 0) {
  $lines.Add("Aucune experience centrale active pour le moment.") | Out-Null
} else {
  foreach ($entry in $selected) {
    $text = [string]$entry.summary
    if ($entry.lesson) { $text = $text + " Lesson: " + [string]$entry.lesson }
    $lines.Add("- [" + [string]$entry.kind + "/" + [string]$entry.category + "] " + $text) | Out-Null
  }
}

$correctionAttempts = @($items | Where-Object { $_.kind -eq "correction_attempt" } | Sort-Object created_at -Descending | Select-Object -First 50)
if ($correctionAttempts.Count -gt 0) {
  $lines.Add("") | Out-Null
  $lines.Add("## Taux de reussite de la correction automatique (50 dernieres tentatives)") | Out-Null
  $lines.Add("") | Out-Null
  $byCategory = $correctionAttempts | Group-Object category
  foreach ($group in $byCategory) {
    $fixed = @($group.Group | Where-Object { $_.context.outcome -eq "fixed" }).Count
    $total = $group.Group.Count
    $percent = if ($total -gt 0) { [Math]::Round(($fixed * 100.0 / $total), 0) } else { 0 }
    $lines.Add("- " + $group.Name + ": " + $fixed + "/" + $total + " (" + $percent + "%)") | Out-Null
  }
}

Write-Utf8NoBom -Path $OutputPath -Content ($lines -join [Environment]::NewLine)
```

- [ ] **Step 2: Write the failing test, then confirm it passes**

Create `tools/tests/Test-HermesReinforcementAggregation.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

$hermesFixture = Join-Path $Root "hermes_lab\reinforcement aggregation fixture\hermes_memory"
if (Test-Path -LiteralPath $hermesFixture) { Remove-Item -LiteralPath $hermesFixture -Recurse -Force }
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null

$addScript = Join-Path $Root "tools\Add-HermesMemoryEntry.ps1"
$fixedContext = (@{ outcome = "fixed"; target_file = "index.html"; attempt_number = 1 } | ConvertTo-Json -Compress)
$notFixedContext = (@{ outcome = "not_fixed"; target_file = "index.html"; attempt_number = 1 } | ConvertTo-Json -Compress)

& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "fixed 1" -ContextJson $fixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "fixed 2" -ContextJson $fixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "dom_reference_check" -Source "test" -Summary "not fixed 1" -ContextJson $notFixedContext | Out-Null
& $addScript -MemoryRoot $hermesFixture -Kind "correction_attempt" -Category "browser_console" -Source "test" -Summary "not fixed 2" -ContextJson $notFixedContext | Out-Null

& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $hermesFixture | Out-Null
$guidance = Get-Content -LiteralPath (Join-Path $hermesFixture "central\guidance_cache.md") -Raw -Encoding UTF8

Assert-True -Condition ($guidance.Contains("Taux de reussite de la correction automatique")) -Message "Guidance should include the reinforcement section header."
Assert-True -Condition ($guidance.Contains("dom_reference_check: 2/3 (67%)")) -Message "dom_reference_check should show 2/3 (67%)."
Assert-True -Condition ($guidance.Contains("browser_console: 0/1 (0%)")) -Message "browser_console should show 0/1 (0%)."

Write-Host "All Test-HermesReinforcementAggregation checks passed."
```

- [ ] **Step 3: Run the new test**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-HermesReinforcementAggregation.ps1`

Expected: `All Test-HermesReinforcementAggregation checks passed.`, exit code 0.

- [ ] **Step 4: Register the suite**

In `tools/tests/Invoke-ControlTowerTestSuite.ps1`, change:

```powershell
  "Test-AutoCorrectionLoop.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

to:

```powershell
  "Test-AutoCorrectionLoop.ps1",
  "Test-HermesReinforcementAggregation.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

- [ ] **Step 5: Run the full suite to confirm nothing else regressed**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1`

Expected: `=== ControlTower test suite passed ===` with all suites listed at exit code 0.

- [ ] **Step 6: Commit**

```bash
git add tools/Get-HermesGuidance.ps1 tools/tests/Test-HermesReinforcementAggregation.ps1 tools/tests/Invoke-ControlTowerTestSuite.ps1
git commit -m "feat: add quantitative per-check success rate to Hermes guidance"
```

---

### Task 5: Screenshot display in the UI

**Files:**
- Modify: `apps/controltower-ui/static/app.js`
- Modify: `apps/controltower-ui/static/styles.css`
- Test: `apps/controltower-ui/tests/test_app.py`

**Interfaces:**
- Consumes: `functionalCheck.screenshot_path` (from Task 1, propagated unchanged through the existing sub-project 1 chain — `functional_check` → run log → `/api/state` → `state.last_run.functional_check` / `job.functional_check`).
- Produces: no new interfaces — this is the last task, purely rendering an existing field.

- [ ] **Step 1: Add an endpoint to serve the screenshot file**

Screenshots are saved under the project's own `validation/screenshot.png` (an arbitrary filesystem path outside the Flask app's static directory), so the browser can't load them directly via `<img src="file:///...">` — add a small route that streams the file. In `apps/controltower-ui/app.py`, add this route right after the existing `/api/report/download` route (find `@app.route("/api/report/download")` and insert after its function body):

```python
    @app.route("/api/screenshot")
    def api_screenshot():
        raw_path = request.args.get("path", "")
        if not raw_path:
            return jsonify({"error": "Chemin manquant."}), 400
        screenshot_path = Path(raw_path)
        if not screenshot_path.exists() or screenshot_path.suffix.lower() != ".png":
            return jsonify({"error": "Capture introuvable."}), 404
        return send_file(str(screenshot_path), mimetype="image/png")
```

- [ ] **Step 2: Write a failing test for the new route**

Append to `apps/controltower-ui/tests/test_app.py`:

```python
def test_screenshot_endpoint_serves_existing_png(client, tmp_path):
    screenshot = tmp_path / "screenshot.png"
    screenshot.write_bytes(b"\x89PNG\r\n\x1a\n" + b"0" * 16)
    response = client.get("/api/screenshot", query_string={"path": str(screenshot)})
    assert response.status_code == 200
    assert response.mimetype == "image/png"


def test_screenshot_endpoint_rejects_missing_file(client, tmp_path):
    missing = tmp_path / "does_not_exist.png"
    response = client.get("/api/screenshot", query_string={"path": str(missing)})
    assert response.status_code == 404
```

- [ ] **Step 3: Run the tests to verify they fail, then pass after Step 1**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: before Step 1's edit, both new tests FAIL (404 route-not-found). After Step 1's edit is in place, re-run and expect all tests (16/16: 14 existing + 2 new) to PASS.

- [ ] **Step 4: Render the screenshot in `renderFunctionalCheck`**

In `apps/controltower-ui/static/app.js`, change:

old:
```javascript
function renderFunctionalCheck(el, functionalCheck) {
  if (!el) return;
  if (!functionalCheck || !functionalCheck.status) {
    el.hidden = true;
    setHtml(el, "");
    return;
  }
  const badgeClass = functionalCheck.status === "ok" ? "ok" : (functionalCheck.status === "failed" ? "bad" : "warn");
  const badgeText = functionalCheck.status === "ok" ? "OK" : (functionalCheck.status === "failed" ? "Echec" : "Non verifie");
  el.hidden = false;
  setHtml(el, `<span class="badge ${badgeClass}">${badgeText}</span>${escapeHtml(functionalCheck.summary || "")}`);
}
```

new:
```javascript
function renderFunctionalCheck(el, functionalCheck) {
  if (!el) return;
  if (!functionalCheck || !functionalCheck.status) {
    el.hidden = true;
    setHtml(el, "");
    return;
  }
  const badgeClass = functionalCheck.status === "ok" ? "ok" : (functionalCheck.status === "failed" ? "bad" : "warn");
  const badgeText = functionalCheck.status === "ok" ? "OK" : (functionalCheck.status === "failed" ? "Echec" : "Non verifie");
  const screenshotHtml = functionalCheck.screenshot_path
    ? `<img class="functional-screenshot" src="/api/screenshot?path=${encodeURIComponent(functionalCheck.screenshot_path)}" alt="Capture d'ecran du plantage">`
    : "";
  el.hidden = false;
  setHtml(el, `<span class="badge ${badgeClass}">${badgeText}</span>${escapeHtml(functionalCheck.summary || "")}${screenshotHtml}`);
}
```

- [ ] **Step 5: Add the CSS**

In `apps/controltower-ui/static/styles.css`, after the existing `.functional-summary .badge` rule, add:

```css
.functional-screenshot {
  display: block;
  max-width: 500px;
  margin-top: 8px;
  border: 1px solid var(--line);
  border-radius: 4px;
}
```

- [ ] **Step 6: Manual verification**

Start the webapp, use `node --check apps/controltower-ui/static/app.js` to confirm no syntax errors, and (if a screenshot fixture from Task 1's Step 2 Fixture C is still on disk) manually fetch `http://127.0.0.1:8899/api/screenshot?path=<absolute-path-to-that-png>` with curl and confirm it returns image bytes with `Content-Type: image/png`.

- [ ] **Step 7: Run the full Flask UI test suite**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: all 16 tests pass.

- [ ] **Step 8: Commit**

```bash
git add apps/controltower-ui/app.py apps/controltower-ui/tests/test_app.py apps/controltower-ui/static/app.js apps/controltower-ui/static/styles.css
git commit -m "feat: display crash screenshot in functional check UI"
```

---

## Final verification

- [ ] `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` — all suites pass, including the two new ones (`Test-AutoCorrectionLoop.ps1`, `Test-HermesReinforcementAggregation.ps1`).
- [ ] `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` — all 16 tests pass.
- [ ] Manual smoke test: recreate a Neon-Paddle-like broken webapp fixture via real Creation, confirm the auto-correction loop actually invokes real Aider, resolves or exhausts its attempts, and the final Hermes guidance reflects an updated success rate for whichever check type was exercised.
- [ ] `git status` — working tree clean.
