# Functional Verification Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real execution-based verification layer (headless browser for webapp projects, syntax + pytest for Python projects) that blocks the pipeline's `passed` status on genuine failures — closing the exact gap that let Neon Paddle be marked `passed` twice while functionally broken — and surface the result in plain French directly in the UI for both the Audit/Correction and Création flows, with a "Corriger ce projet" action when Création fails.

**Architecture:** A new standalone PowerShell script (`tools/Test-ProjectFunctional.ps1`) dispatches by project type to either a Python-native check (syntax + pytest, no new dependency) or a new Node/Playwright headless-browser checker (`tools/headless/check-webapp.js`, new dependency). Its JSON result is folded into `Test-AiderCreation.ps1`/`Test-AiderFix.ps1`'s existing pass/fail logic, threaded through `Invoke-ControlTowerRun.ps1` into the run log, and rendered in the Flask UI as a distinct badge + plain-language sentence in both tabs, plus a correction flow reusing the pipeline's existing `-AllowExisting` support.

**Tech Stack:** PowerShell 5.1/7, Python 3.12 (Flask), Node.js + Playwright (new), vanilla JS/CSS (existing `apps/controltower-ui/static/`).

## Global Constraints

- Audit mode is explicitly **not** covered — it produces a report, not executable code. Only Creation and Fix get the functional check.
- No deep interactive browser testing — only initial page load + console/pageerror capture for a few seconds. No AST parsing of JS — regex-based DOM cross-reference, same pragmatic-heuristic philosophy as the existing mojibake detectors in this codebase.
- Every check must be general-purpose — no logic may reference a specific project name or brief content.
- A functional `status: "failed"` must make the overall pipeline validation `failed`, never `passed` — this is the anti-false-positive principle the whole sub-project exists to enforce.
- A project type/state that cannot be verified (`not_verified`) must never block the pipeline — only a genuine, positively-detected failure blocks.
- Every plain-language summary must be understandable without technical background — no stack traces, no jargon, in the first sentence shown to the user (technical detail can exist in a secondary `checks[].detail` field).
- Every new capability visible to the user must actually appear in the UI — never leave a backend-only signal unexposed.
- Test commands: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` (PowerShell suites) and `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` (Flask UI) from repo root.

---

### Task 1: Headless browser checker (`tools/headless/`)

**Files:**
- Create: `tools/headless/package.json`
- Create: `tools/headless/check-webapp.js`

**Interfaces:**
- Produces: `node tools/headless/check-webapp.js <projectDir>` — prints one JSON object to stdout: `{ "status": "ok"|"failed"|"not_verified", "summary": "<French sentence>", "checks": [{ "name": string, "status": "ok"|"failed"|"not_verified", "detail": string }] }`. Always exits 0 (the caller inspects `status` in the JSON, not the exit code — this script never crashes the calling process even on a "failed" verification result).

- [ ] **Step 1: Create the package manifest**

Create `tools/headless/package.json`:

```json
{
  "name": "controltower-headless-checks",
  "version": "1.0.0",
  "private": true,
  "description": "Verification headless des projets webapp generes par ControlTower",
  "dependencies": {
    "playwright": "^1.48.0"
  }
}
```

- [ ] **Step 2: Write the checker script**

Create `tools/headless/check-webapp.js`:

```javascript
const fs = require('fs');
const path = require('path');

async function main() {
  const projectPath = process.argv[2];
  if (!projectPath) {
    console.log(JSON.stringify({ status: 'not_verified', summary: 'Chemin de projet manquant.', checks: [] }));
    return;
  }

  const checks = [];
  let htmlPath = path.join(projectPath, 'index.html');
  if (!fs.existsSync(htmlPath)) {
    const found = fs.readdirSync(projectPath).find((f) => f.toLowerCase().endsWith('.html'));
    if (found) {
      htmlPath = path.join(projectPath, found);
    } else {
      console.log(JSON.stringify({ status: 'not_verified', summary: 'Aucun fichier HTML trouve a la racine du projet.', checks: [] }));
      return;
    }
  }

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
  for (const rel of scriptFiles) {
    const jsPath = path.join(projectPath, rel);
    if (!fs.existsSync(jsPath)) continue;
    const js = fs.readFileSync(jsPath, 'utf8');
    for (const m of js.matchAll(/getElementById\(\s*['"]([^'"]+)['"]\s*\)/g)) {
      if (!htmlIds.has(m[1])) missingRefs.push({ kind: 'id', name: m[1], file: rel });
    }
    for (const m of js.matchAll(/querySelector\(\s*['"]#([A-Za-z0-9_-]+)['"]\s*\)/g)) {
      if (!htmlIds.has(m[1])) missingRefs.push({ kind: 'id', name: m[1], file: rel });
    }
    for (const m of js.matchAll(/querySelector\(\s*['"]\.([A-Za-z0-9_-]+)['"]\s*\)/g)) {
      if (!htmlClasses.has(m[1])) missingRefs.push({ kind: 'class', name: m[1], file: rel });
    }
  }

  checks.push({
    name: 'dom_reference_check',
    status: missingRefs.length === 0 ? 'ok' : 'failed',
    detail: missingRefs.map((r) => `${r.file}: reference a "${r.name}" (${r.kind}) introuvable dans le HTML`).join('; ')
  });

  if (missingRefs.length > 0) {
    const first = missingRefs[0];
    console.log(JSON.stringify({
      status: 'failed',
      summary: `Le code cherche un element "${first.name}" qui n'existe pas dans la page (${first.file}).`,
      checks
    }));
    return;
  }

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
    await page.goto('file://' + htmlPath.replace(/\\/g, '/'));
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
}

main().catch((err) => {
  console.log(JSON.stringify({ status: 'not_verified', summary: 'Erreur inattendue pendant la verification: ' + err.message, checks: [] }));
});
```

- [ ] **Step 3: Install dependencies and the Chromium browser**

Run (from `tools/headless/`): `npm install` then `npx playwright install chromium`

Expected: both commands complete without error; `tools/headless/node_modules/` and a local Playwright Chromium download exist afterward.

- [ ] **Step 4: Manually verify against a "good" fixture**

Create a scratch fixture (outside the repo, e.g. under the OS temp directory) with:

`index.html`:
```html
<!doctype html>
<html><body><div id="app">Hello</div><script src="app.js"></script></body></html>
```

`app.js`:
```javascript
document.getElementById('app').textContent = 'Loaded';
```

Run: `node tools/headless/check-webapp.js <path-to-fixture-dir>`

Expected: JSON with `"status": "ok"`.

- [ ] **Step 5: Manually verify against a "missing DOM reference" fixture**

Same fixture but with `index.html` changed to `<html><body><script src="app.js"></script></body></html>` (no `#app` div), same `app.js`.

Run: `node tools/headless/check-webapp.js <path-to-fixture-dir>`

Expected: JSON with `"status": "failed"`, `summary` mentioning `"app"` and `app.js` — this is the exact class of bug that caused Neon Paddle's original false pass.

- [ ] **Step 6: Manually verify against a "console error on load" fixture**

`index.html`: `<html><body><div id="app"></div><script src="app.js"></script></body></html>` (matching id present).
`app.js`: `null.crashHere();`

Run: `node tools/headless/check-webapp.js <path-to-fixture-dir>`

Expected: JSON with `"status": "failed"`, `summary` starting with "Le site plante des l'ouverture".

- [ ] **Step 7: Commit**

```bash
git add tools/headless/package.json tools/headless/check-webapp.js
git commit -m "feat: add headless browser checker for webapp functional verification"
```

Note: do not commit `tools/headless/node_modules/` — check `.gitignore` already excludes `node_modules/` broadly; if it doesn't, add `tools/headless/node_modules/` to `.gitignore` in this same commit.

---

### Task 2: `Test-ProjectFunctional.ps1` — the verification engine

**Files:**
- Create: `tools/Test-ProjectFunctional.ps1`
- Create: `tools/tests/Test-ProjectFunctionalCheck.ps1`
- Modify: `tools/tests/Invoke-ControlTowerTestSuite.ps1` (register the new suite)

**Interfaces:**
- Consumes: `tools/headless/check-webapp.js` (Task 1), invoked as `node <path> <projectDir>`, expects the JSON shape from Task 1's Interfaces.
- Produces: `powershell -File tools/Test-ProjectFunctional.ps1 -ProjectPath <path> [-ProjectType <type>]` — prints one JSON object to stdout with the same shape as Task 1 (`status`, `summary`, `checks`), exits 0 if `status` is `"ok"` or `"not_verified"`, exits 1 if `"failed"`. This is what Task 3 calls.

- [ ] **Step 1: Write the engine script**

Create `tools/Test-ProjectFunctional.ps1`:

```powershell
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
  foreach ($file in $pyFiles) {
    & $python.exe @($python.args) -m py_compile $file.FullName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $syntaxErrors += $file.FullName }
  }
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
  try {
    $testOutput = & $python.exe @($python.args) -m pytest 2>&1
    $testExit = $LASTEXITCODE
  } finally {
    Pop-Location
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
  $output = & $node.Source $checkerScript $ProjectPath 2>&1
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
```

- [ ] **Step 2: Write the test suite with fixtures for every branch**

Create `tools/tests/Test-ProjectFunctionalCheck.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$engine = Join-Path $Root "tools\Test-ProjectFunctional.ps1"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function New-Fixture {
  param([string]$Name)
  $path = Join-Path $Root ("hermes_lab\functional check fixtures\" + $Name)
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

Write-Host "=== Test-ProjectFunctional: webapp ok ==="
$fixture = New-Fixture -Name "webapp_ok"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><div id="app"></div><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "webapp" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: webapp missing DOM reference ==="
$fixture = New-Fixture -Name "webapp_missing_dom"
Set-Content -LiteralPath (Join-Path $fixture "index.html") -Value '<html><body><script src="app.js"></script></body></html>'
Set-Content -LiteralPath (Join-Path $fixture "app.js") -Value "document.getElementById('app').textContent = 'ok';"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "webapp" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)
Assert-True -Condition ($result.summary.Contains("app")) -Message "Summary should mention the missing element id."

Write-Host "=== Test-ProjectFunctional: python syntax error ==="
$fixture = New-Fixture -Name "python_syntax_error"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def broken(:"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: python no tests ==="
$fixture = New-Fixture -Name "python_no_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)
Assert-True -Condition ($result.summary.Contains("aucun test")) -Message "Summary should be honest about no tests existing."

Write-Host "=== Test-ProjectFunctional: python failing tests ==="
$fixture = New-Fixture -Name "python_failing_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a - b`n"
New-Item -ItemType Directory -Path (Join-Path $fixture "tests") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture "tests\test_main.py") -Value "import sys, os`nsys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))`nfrom main import add`ndef test_add():`n    assert add(2, 3) == 5`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "failed") -Message ("Expected failed, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: python passing tests ==="
$fixture = New-Fixture -Name "python_passing_tests"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
New-Item -ItemType Directory -Path (Join-Path $fixture "tests") -Force | Out-Null
Set-Content -LiteralPath (Join-Path $fixture "tests\test_main.py") -Value "import sys, os`nsys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))`nfrom main import add`ndef test_add():`n    assert add(2, 3) == 5`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "python-cli" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: not verified (empty dir, desktop type) ==="
$fixture = New-Fixture -Name "not_verified"
Set-Content -LiteralPath (Join-Path $fixture "readme.txt") -Value "nothing recognizable here"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture -ProjectType "desktop" | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "not_verified") -Message ("Expected not_verified, got " + $result.status)

Write-Host "=== Test-ProjectFunctional: auto-detect with no declared type (Fix mode simulation) ==="
$fixture = New-Fixture -Name "auto_detect_python"
Set-Content -LiteralPath (Join-Path $fixture "main.py") -Value "def add(a, b):`n    return a + b`n"
$json = & powershell -ExecutionPolicy Bypass -File $engine -ProjectPath $fixture | Out-String
$result = $json | ConvertFrom-Json
Assert-True -Condition ($result.status -eq "ok") -Message ("Expected ok via auto-detection, got " + $result.status)

Write-Host ""
Write-Host "All Test-ProjectFunctional checks passed."
```

- [ ] **Step 3: Run the new suite directly**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-ProjectFunctionalCheck.ps1`

Expected: `All Test-ProjectFunctional checks passed.`, exit code 0. This exercises Task 1's `check-webapp.js` too — if it fails on the webapp cases, verify Task 1's manual checks (Steps 4-6) still pass in isolation first.

- [ ] **Step 4: Register the suite**

In `tools/tests/Invoke-ControlTowerTestSuite.ps1`, change:

```powershell
$Suites = @(
  "Test-PowerShellEncodingLint.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

to:

```powershell
$Suites = @(
  "Test-PowerShellEncodingLint.ps1",
  "Test-ProjectFunctionalCheck.ps1",
  "Test-AiderReliabilityLayer.ps1",
```

- [ ] **Step 5: Commit**

```bash
git add tools/Test-ProjectFunctional.ps1 tools/tests/Test-ProjectFunctionalCheck.ps1 tools/tests/Invoke-ControlTowerTestSuite.ps1
git commit -m "feat: add functional verification engine (Python + webapp dispatch)"
```

---

### Task 3: Integrate into `Test-AiderCreation.ps1` and `Test-AiderFix.ps1`

**Files:**
- Modify: `tools/Test-AiderCreation.ps1:159-219`
- Modify: `tools/Test-AiderFix.ps1:126-161`

**Interfaces:**
- Consumes: `tools/Test-ProjectFunctional.ps1` (Task 2) — invoked as `powershell -File <path> -ProjectPath <dir> [-ProjectType <type>]`, JSON stdout with `status`/`summary`/`checks`.
- Produces: both scripts' output JSON (`creation_result.json`, `<ticketId>_result.json`) gain a `functional_check` key with the full `{ status, summary, checks }` object. Their overall `passed` boolean now also requires `functional_check.status -ne "failed"`. Task 4 reads this new key.

- [ ] **Step 1: Wire the check into `Test-AiderCreation.ps1`**

In `tools/Test-AiderCreation.ps1`, the config is already loaded as `$config` near the top (line 81: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`), which has a `project_type` field (confirmed in `creation.config.json`'s schema). Change the `$readmeOk`/`$usefulChangeOk`/`$passed` block (currently lines 159-162):

old:
```powershell
$readmePath = Join-Path $target "README.md"
$readmeOk = (Test-Path -LiteralPath $readmePath -PathType Leaf) -and ((Get-Item -LiteralPath $readmePath).Length -gt 40)
$usefulChangeOk = ((-not $RequireUsefulChanges) -or ($usefulChanges.Count -gt 0))
$passed = (($forbidden.Count -eq 0) -and ($suspiciousFiles.Count -eq 0) -and ($encodingFindings.Count -eq 0) -and $readmeOk -and ($currentMap.Keys.Count -gt 0) -and $usefulChangeOk)
```

new:
```powershell
$readmePath = Join-Path $target "README.md"
$readmeOk = (Test-Path -LiteralPath $readmePath -PathType Leaf) -and ((Get-Item -LiteralPath $readmePath).Length -gt 40)
$usefulChangeOk = ((-not $RequireUsefulChanges) -or ($usefulChanges.Count -gt 0))
$structurallyOk = (($forbidden.Count -eq 0) -and ($suspiciousFiles.Count -eq 0) -and ($encodingFindings.Count -eq 0) -and $readmeOk -and ($currentMap.Keys.Count -gt 0) -and $usefulChangeOk)
$functionalCheck = [ordered]@{ status = "not_verified"; summary = "Verification fonctionnelle non executee."; checks = @() }
if ($structurallyOk) {
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $target -ProjectType ([string]$config.project_type) | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
  }
}
$passed = $structurallyOk -and ($functionalCheck.status -ne "failed")
```

Then change the `$result` block (currently lines 164-178):

old:
```powershell
$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace_path = $workspace
  target_project_path = $target
  changes = $changes
  useful_changes = $usefulChanges
  forbidden_files = $forbidden
  suspicious_files = $suspiciousFiles
  ghost_findings = $ghostFindings
  encoding_findings = $encodingFindings
  readme_ok = $readmeOk
  require_useful_changes = [bool]$RequireUsefulChanges
  useful_change_ok = $usefulChangeOk
  passed = $passed
}
```

new:
```powershell
$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  workspace_path = $workspace
  target_project_path = $target
  changes = $changes
  useful_changes = $usefulChanges
  forbidden_files = $forbidden
  suspicious_files = $suspiciousFiles
  ghost_findings = $ghostFindings
  encoding_findings = $encodingFindings
  readme_ok = $readmeOk
  require_useful_changes = [bool]$RequireUsefulChanges
  useful_change_ok = $usefulChangeOk
  functional_check = $functionalCheck
  passed = $passed
}
```

Then, right before the final `if ($passed) { ... }` block (currently starting at line 210), add a functional-check summary to the console output. Change:

old:
```powershell
if (-not $usefulChangeOk) {
  Write-Host ""
  Write-Host "No useful generated project changes were detected."
}

if ($passed) {
```

new:
```powershell
if (-not $usefulChangeOk) {
  Write-Host ""
  Write-Host "No useful generated project changes were detected."
}
Write-Host ""
Write-Host ("Functional check: " + $functionalCheck.status + " - " + $functionalCheck.summary)

if ($passed) {
```

- [ ] **Step 2: Wire the check into `Test-AiderFix.ps1`**

In `tools/Test-AiderFix.ps1`, the check operates on `$snapshot` (the corrected copy), not the original project, and there's no declared project type in Fix mode (the engine auto-detects). Change the `$failedCommands`/`$passed`/`$result` block (currently lines 126-136):

old:
```powershell
$failedCommands = @($commandResults | Where-Object { $_.exit_code -ne 0 })
$passed = (($unauthorized.Count -eq 0) -and ($ghostFindings.Count -eq 0) -and ($failedCommands.Count -eq 0))
$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  ticket = $safeId
  changes = $changes
  unauthorized_changes = $unauthorized
  ghost_findings = $ghostFindings
  command_results = $commandResults
  passed = $passed
}
```

new:
```powershell
$failedCommands = @($commandResults | Where-Object { $_.exit_code -ne 0 })
$structurallyOk = (($unauthorized.Count -eq 0) -and ($ghostFindings.Count -eq 0) -and ($failedCommands.Count -eq 0))
$functionalCheck = [ordered]@{ status = "not_verified"; summary = "Verification fonctionnelle non executee."; checks = @() }
if ($structurallyOk) {
  $functionalScript = Join-Path $PSScriptRoot "Test-ProjectFunctional.ps1"
  if (Test-Path -LiteralPath $functionalScript) {
    $functionalOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $snapshot | Out-String
    try {
      $functionalCheck = $functionalOutput | ConvertFrom-Json
    } catch {
      $functionalCheck = [ordered]@{ status = "not_verified"; summary = "La verification fonctionnelle n'a pas pu s'executer correctement."; checks = @() }
    }
  }
}
$passed = $structurallyOk -and ($functionalCheck.status -ne "failed")
$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  ticket = $safeId
  changes = $changes
  unauthorized_changes = $unauthorized
  ghost_findings = $ghostFindings
  command_results = $commandResults
  functional_check = $functionalCheck
  passed = $passed
}
```

Then, right before the final `if ($passed) { ... }` block (currently starting at line 155), add the functional summary to console output. Change:

old:
```powershell
if ($ghostFindings.Count -gt 0) {
  Write-Host ""
  Write-Host "Ghost findings:"
  $ghostFindings | ForEach-Object { Write-Host ("- " + $_.path + ": " + $_.marker) }
}

if ($passed) {
```

new:
```powershell
if ($ghostFindings.Count -gt 0) {
  Write-Host ""
  Write-Host "Ghost findings:"
  $ghostFindings | ForEach-Object { Write-Host ("- " + $_.path + ": " + $_.marker) }
}
Write-Host ""
Write-Host ("Functional check: " + $functionalCheck.status + " - " + $functionalCheck.summary)

if ($passed) {
```

- [ ] **Step 3: Verify with a real fixture through the reliability suites**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-AiderCreationReliability.ps1"`

Expected: exit 0. This suite's fixture is a minimal Python CLI seeded with a README/pyproject/src/tests structure and no real Aider run (dry-run), so `functional_check` should come back `not_verified` or `ok` (no tests are actually generated in dry-run) — the important thing is the suite still passes end to end without throwing on the new code path.

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-AiderFixReliability.ps1"`

Expected: exit 0, same reasoning.

- [ ] **Step 4: Commit**

```bash
git add tools/Test-AiderCreation.ps1 tools/Test-AiderFix.ps1
git commit -m "feat: block creation/fix validation on functional check failures"
```

---

### Task 4: Propagate `functional_check` through the run log to the Flask API

**Files:**
- Modify: `tools/Invoke-AiderFixPipeline.ps1:58-73` (copy `functional_check` from the validator's result into the pipeline's own summary)
- Modify: `tools/Invoke-ControlTowerRun.ps1:158-164` (Fix mode `$result`), `:191-198` (Creation mode `$result`)
- Modify: `apps/controltower-ui/app.py:660-670` (`read_last_run_status()`)

**Interfaces:**
- Consumes: `functional_check` key in `<ticketId>_pipeline_result.json` (Fix) / `creation_result.json` (Creation), produced by Task 3 (Fix's copy is relayed by this task's Step 0 below).
- Produces: `read_last_run_status()`'s return dict gains a `functional_check` key (same `{status, summary, checks}` shape, or `null` if absent/unavailable). Task 6 (UI) reads `state.last_run.functional_check`.

- [ ] **Step 0: Relay `functional_check` into the Fix pipeline's own summary file**

`Invoke-ControlTowerRun.ps1`'s existing `Get-PipelineStatus` call for Fix mode reads `<ticketId>_pipeline_result.json` — a *separate* summary file written by `Invoke-AiderFixPipeline.ps1` itself, not `Test-AiderFix.ps1`'s own `<safeId>_result.json` (confirmed by reading both files: `Invoke-AiderFixPipeline.ps1` derives its own coarse `validation: passed/failed` from `$LASTEXITCODE` rather than forwarding the validator's detailed result). `functional_check` must be relayed through this same file, or `Invoke-ControlTowerRun.ps1` would read the wrong path.

In `tools/Invoke-AiderFixPipeline.ps1`, change:

old:
```powershell
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
```

new:
```powershell
$validation = "skipped"
$functionalCheck = $null
if ($RunAider -or $ValidateAfterDryRun) {
  & $testScript -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack
  $validation = if ($LASTEXITCODE -eq 0) { "passed" } else { "failed" }
  $validationResultPath = Join-Path $workspace ("validation\" + $safeId + "_result.json")
  if (Test-Path -LiteralPath $validationResultPath) {
    $validationResult = Get-Content -LiteralPath $validationResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $functionalCheck = $validationResult.functional_check
  }
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
  functional_check = $functionalCheck
} | ConvertTo-Json -Depth 6)
```

- [ ] **Step 1: Read `functional_check` in `Invoke-ControlTowerRun.ps1`**

In `tools/Invoke-ControlTowerRun.ps1`, change the Fix mode block:

old:
```powershell
    $result = @{
      workspace_path = $workspace
      ticket_path = $ticket
      pipeline = "fix"
    }
    $ticketId = [System.IO.Path]::GetFileNameWithoutExtension($ticket)
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName ($ticketId + "_pipeline_result.json")
```

new:
```powershell
    $ticketId = [System.IO.Path]::GetFileNameWithoutExtension($ticket)
    $fixPipelineResultPath = Join-Path $workspace ("validation\" + $ticketId + "_pipeline_result.json")
    $functionalCheck = $null
    if (Test-Path -LiteralPath $fixPipelineResultPath) {
      $fixPipelineResult = Get-Content -LiteralPath $fixPipelineResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $functionalCheck = $fixPipelineResult.functional_check
    }
    $result = @{
      workspace_path = $workspace
      ticket_path = $ticket
      pipeline = "fix"
      functional_check = $functionalCheck
    }
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName ($ticketId + "_pipeline_result.json")
```

Then change the Creation mode block:

old:
```powershell
    $result = @{
      project_name = $ProjectName
      project_type = $ProjectType
      workspace_path = $workspace
      target_project_path = [string]$config.target_project_path
      pipeline = "creation"
    }
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName "pipeline_result.json"
```

new:
```powershell
    $creationResultPath = Join-Path $workspace "validation\creation_result.json"
    $functionalCheck = $null
    if (Test-Path -LiteralPath $creationResultPath) {
      $creationResult = Get-Content -LiteralPath $creationResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
      $functionalCheck = $creationResult.functional_check
    }
    $result = @{
      project_name = $ProjectName
      project_type = $ProjectType
      workspace_path = $workspace
      target_project_path = [string]$config.target_project_path
      pipeline = "creation"
      functional_check = $functionalCheck
    }
    $status = Get-PipelineStatus -Workspace $workspace -ResultFileName "pipeline_result.json"
```

- [ ] **Step 2: Expose it in `read_last_run_status()`**

In `apps/controltower-ui/app.py`, change:

old:
```python
def read_last_run_status():
    artifacts = latest_artifacts()
    run_log = artifacts.get("run_log")
    if not run_log:
        return {"status": "idle", "label": "En attente", "artifacts": artifacts}
    try:
        payload = json.loads(Path(run_log).read_text(encoding="utf-8"))
        status = payload.get("status", "observed")
    except Exception:
        status = "observed"
    return {"status": status, "label": status_label(status), "artifacts": artifacts}
```

new:
```python
def read_last_run_status():
    artifacts = latest_artifacts()
    run_log = artifacts.get("run_log")
    if not run_log:
        return {"status": "idle", "label": "En attente", "artifacts": artifacts, "functional_check": None}
    try:
        payload = json.loads(Path(run_log).read_text(encoding="utf-8"))
        status = payload.get("status", "observed")
        functional_check = (payload.get("data") or {}).get("functional_check")
    except Exception:
        status = "observed"
        functional_check = None
    return {"status": status, "label": status_label(status), "artifacts": artifacts, "functional_check": functional_check}
```

- [ ] **Step 3: Verify end to end**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-ControlTowerOrchestrator.ps1"`

Expected: exit 0 (this suite runs a real Audit dry-run through `Invoke-ControlTowerRun.ps1` end to end and would fail if the Fix/Creation block edits introduced a syntax error — Audit mode itself is untouched by this task, but a parse error anywhere in the file would break every mode).

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: all existing tests still pass (the `functional_check` key addition to `read_last_run_status()`'s return value is additive, not a breaking change to any existing assertion).

- [ ] **Step 4: Commit**

```bash
git add tools/Invoke-AiderFixPipeline.ps1 tools/Invoke-ControlTowerRun.ps1 apps/controltower-ui/app.py
git commit -m "feat: propagate functional_check through run log to /api/state"
```

---

### Task 5: Dependency observability (Node/Playwright)

**Files:**
- Modify: `tools/Test-ControlTowerDependencies.ps1`
- Modify: `tools/Install-ControlTower.ps1`

**Interfaces:**
- Produces: `Test-ControlTowerDependencies.ps1`'s `$result` gains a `headless_browser` key: `{ name: "Playwright", available: bool }` — visible in the existing dependency panel automatically (no UI code needed, same mechanism as `serving_health` from the prior sub-project).

- [ ] **Step 1: Add the check function**

In `tools/Test-ControlTowerDependencies.ps1`, after the existing `Test-OllamaServingHealth` function (ends at line 60), insert:

```powershell
function Test-HeadlessBrowser {
  param([string]$ScriptRoot)
  $nodeAvailable = $null -ne (Get-Command "node" -ErrorAction SilentlyContinue)
  $playwrightPath = Join-Path $ScriptRoot "headless\node_modules\playwright"
  $playwrightAvailable = $nodeAvailable -and (Test-Path -LiteralPath $playwrightPath)
  return [ordered]@{ name = "Playwright"; available = $playwrightAvailable }
}
```

- [ ] **Step 2: Wire it into `$result`**

In `tools/Test-ControlTowerDependencies.ps1`, change:

old:
```powershell
  ornith = Test-OllamaModel -ModelName "ornith:9b"
  serving_health = Test-OllamaServingHealth -ModelName "ornith:9b"
  hermes = [ordered]@{
```

new:
```powershell
  ornith = Test-OllamaModel -ModelName "ornith:9b"
  serving_health = Test-OllamaServingHealth -ModelName "ornith:9b"
  headless_browser = Test-HeadlessBrowser -ScriptRoot $PSScriptRoot
  hermes = [ordered]@{
```

- [ ] **Step 3: Verify manually**

Run: `powershell -ExecutionPolicy Bypass -File tools\Test-ControlTowerDependencies.ps1 -ProjectPath "C:\AI_ControlTower" -HermesMemoryRoot "C:\AI_ControlTower\hermes_memory"`

Expected: JSON output includes `"headless_browser": { "name": "Playwright", "available": true }` (Task 1 already installed it on this machine).

- [ ] **Step 4: Add the npm install step to `Install-ControlTower.ps1`**

In `tools/Install-ControlTower.ps1`, change:

old:
```powershell
$initHermes = Join-Path $Root "tools\Initialize-HermesMemory.ps1"
if (-not (Test-Path -LiteralPath $initHermes)) {
  throw "Initialize-HermesMemory.ps1 introuvable: $initHermes"
}
& $initHermes -MemoryRoot $HermesMemoryRoot | Out-Null
```

new:
```powershell
$initHermes = Join-Path $Root "tools\Initialize-HermesMemory.ps1"
if (-not (Test-Path -LiteralPath $initHermes)) {
  throw "Initialize-HermesMemory.ps1 introuvable: $initHermes"
}
& $initHermes -MemoryRoot $HermesMemoryRoot | Out-Null

$headlessDir = Join-Path $Root "tools\headless"
if ((Test-Path -LiteralPath (Join-Path $headlessDir "package.json")) -and (Get-Command "npm" -ErrorAction SilentlyContinue)) {
  Push-Location $headlessDir
  try {
    & npm install
    & npx playwright install chromium
  } finally {
    Pop-Location
  }
} else {
  Write-Host "npm introuvable ou tools/headless absent: verification navigateur non installee."
}
```

- [ ] **Step 5: Commit**

```bash
git add tools/Test-ControlTowerDependencies.ps1 tools/Install-ControlTower.ps1
git commit -m "feat: surface headless browser availability in dependency check"
```

---

### Task 6: Surface functional check status in both UI views

**Files:**
- Modify: `apps/controltower-ui/templates/index.html`
- Modify: `apps/controltower-ui/static/app.js`
- Modify: `apps/controltower-ui/static/styles.css`

**Interfaces:**
- Consumes: `state.last_run.functional_check` from `/api/state` (Task 4), shape `{ status: "ok"|"failed"|"not_verified", summary: string, checks: [...] } | null`.
- Produces: `renderFunctionalCheck(el, functionalCheck)` — a new shared JS function both views call; no other task depends on this.

- [ ] **Step 1: Add the CSS badge variant**

In `apps/controltower-ui/static/styles.css`, after the existing `.badge.bad` rule (currently ending around line 352), add:

```css
.badge.warn {
  background: #fdf0e3;
  color: var(--warn);
}
```

- [ ] **Step 2: Add the HTML slot in the Audit/Correction view**

In `apps/controltower-ui/templates/index.html`, inside the `.status-band` section, change:

old:
```html
      <section class="status-band">
        <div>
          <span class="eyebrow">Dernier run audit</span>
          <strong id="lastRunStatus">En attente</strong>
        </div>
        <div id="artifactLinks" class="artifact-links"></div>
        <div id="reportActions" class="report-actions">
          <button id="readReportButton" class="secondary" type="button">Lire le rapport</button>
          <button id="downloadReportButton" class="secondary" type="button">Telecharger</button>
        </div>
      </section>
```

new:
```html
      <section class="status-band">
        <div>
          <span class="eyebrow">Dernier run audit</span>
          <strong id="lastRunStatus">En attente</strong>
          <p id="lastRunFunctional" class="functional-summary" hidden></p>
        </div>
        <div id="artifactLinks" class="artifact-links"></div>
        <div id="reportActions" class="report-actions">
          <button id="readReportButton" class="secondary" type="button">Lire le rapport</button>
          <button id="downloadReportButton" class="secondary" type="button">Telecharger</button>
        </div>
      </section>
```

- [ ] **Step 3: Add the HTML panel in the Création view**

In `apps/controltower-ui/templates/index.html`, inside `#creationView`'s `.creation-status` panel, change:

old:
```html
        <section class="panel creation-status">
          <h2>Journal creation</h2>
          <div id="creationJobPanel" class="job-panel"></div>
          <div id="creationLogPanel" class="log-panel creation-log"></div>
        </section>
```

new:
```html
        <section class="panel creation-status">
          <h2>Journal creation</h2>
          <p id="creationFunctional" class="functional-summary" hidden></p>
          <div id="creationJobPanel" class="job-panel"></div>
          <div id="creationLogPanel" class="log-panel creation-log"></div>
        </section>
```

- [ ] **Step 4: Add the CSS for `.functional-summary`**

In `apps/controltower-ui/static/styles.css`, after the `.badge.warn` rule added in Step 1, add:

```css
.functional-summary {
  margin-top: 6px;
  font-size: 13px;
}

.functional-summary .badge {
  margin-right: 6px;
}
```

- [ ] **Step 5: Add the element references and shared render function**

In `apps/controltower-ui/static/app.js`, change the `els` object (add two new lines right after the existing `lastRunStatus` line):

old:
```javascript
  lastRunStatus: document.getElementById("lastRunStatus"),
  artifactLinks: document.getElementById("artifactLinks"),
```

new:
```javascript
  lastRunStatus: document.getElementById("lastRunStatus"),
  lastRunFunctional: document.getElementById("lastRunFunctional"),
  artifactLinks: document.getElementById("artifactLinks"),
```

Then add `creationFunctional` right after the existing `creationLogPanel` line:

old:
```javascript
  creationJobPanel: document.getElementById("creationJobPanel"),
  creationLogPanel: document.getElementById("creationLogPanel"),
```

new:
```javascript
  creationJobPanel: document.getElementById("creationJobPanel"),
  creationLogPanel: document.getElementById("creationLogPanel"),
  creationFunctional: document.getElementById("creationFunctional"),
```

Then add a shared render helper right after the existing `statusBadge` function:

old:
```javascript
function statusBadge(ok) {
  return `<span class="badge ${ok ? "ok" : "bad"}">${ok ? "OK" : "Absent"}</span>`;
}
```

new:
```javascript
function statusBadge(ok) {
  return `<span class="badge ${ok ? "ok" : "bad"}">${ok ? "OK" : "Absent"}</span>`;
}

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

- [ ] **Step 6: Call it from `renderLastRun` (Audit/Correction view)**

In `apps/controltower-ui/static/app.js`, change:

old:
```javascript
function renderLastRun(lastRun) {
  if (!els.lastRunStatus && !els.artifactLinks) return;
  const info = lastRun || {};
  setText(els.lastRunStatus, info.label || "En attente");
```

new:
```javascript
function renderLastRun(lastRun) {
  if (!els.lastRunStatus && !els.artifactLinks) return;
  const info = lastRun || {};
  setText(els.lastRunStatus, info.label || "En attente");
  renderFunctionalCheck(els.lastRunFunctional, info.functional_check);
```

- [ ] **Step 7: Call it from `renderCreationJobs` (Création view)**

The Création view doesn't get its status from `state.last_run` (which reflects whatever mode last ran across the whole app, audit or creation) — it needs the functional check tied to the *creation* job specifically, not the global last run. Since `renderCreationJobs` already receives the list of jobs and picks the relevant creation job, extend it to read `job.functional_check` if present (this field will be populated by Task 8, which adds it to the job dict when a creation job finishes — for now, this task only wires the rendering so Task 8 has nothing left to do on the JS side beyond producing the data).

In `apps/controltower-ui/static/app.js`, change:

old:
```javascript
function renderCreationJobs(jobs) {
  if (!els.creationJobPanel) return;
  const creationJobs = (jobs || []).filter((job) => job.command === "new_project");
  const runningJob = creationJobs.find((job) => job.status === "queued" || job.status === "running");
  const job = runningJob || creationJobs[creationJobs.length - 1];
  if (!job) {
    setHtml(els.creationJobPanel, "");
    return;
  }
```

new:
```javascript
function renderCreationJobs(jobs) {
  if (!els.creationJobPanel) return;
  const creationJobs = (jobs || []).filter((job) => job.command === "new_project");
  const runningJob = creationJobs.find((job) => job.status === "queued" || job.status === "running");
  const job = runningJob || creationJobs[creationJobs.length - 1];
  if (!job) {
    setHtml(els.creationJobPanel, "");
    renderFunctionalCheck(els.creationFunctional, null);
    return;
  }
  renderFunctionalCheck(els.creationFunctional, job.functional_check);
```

- [ ] **Step 8: Manual verification**

Start the webapp (`python apps/controltower-ui/app.py --project-path C:\AI_ControlTower`), open it in a browser, and confirm: (a) the page loads with no console errors, (b) `#lastRunFunctional` and `#creationFunctional` are both `hidden` when no `functional_check` data exists yet (no visual regression on a fresh load).

- [ ] **Step 9: Run the Flask UI test suite**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: all tests still pass (this task is pure frontend + one new render call reading an already-present-but-currently-always-null field — no backend behavior changed).

- [ ] **Step 10: Commit**

```bash
git add apps/controltower-ui/templates/index.html apps/controltower-ui/static/app.js apps/controltower-ui/static/styles.css
git commit -m "feat: display functional check status in audit and creation views"
```

---

### Task 7: Backend support for `allow_existing` / `correction_notes`

**Files:**
- Modify: `apps/controltower-ui/app.py`
- Test: `apps/controltower-ui/tests/test_app.py`

**Interfaces:**
- Produces: `validate_new_project_payload(payload)` accepts an `allow_existing` flag and skips the "must be empty" check when true. `build_new_project_command(payload, run_aider, persist_brief, allow_existing=False, correction_notes="")` — when `allow_existing` is true and `correction_notes` is non-empty, locates the most recent creation workspace whose `target_project_path` matches, reads its `project_brief.md`, appends a `## Correction requise` section, persists a new brief file, and adds `-AllowExisting` to the command/args. New route `GET /api/new-project/status?project_name=...&parent_path=...` returns `{ has_previous: bool, functional_status: str|None, checks: list }`. `create_new_project_job` and `run_dynamic_job`'s job dict gain a `functional_check` field (populated after the job finishes, read from the workspace's `validation/creation_result.json`) — this is what Task 6's `renderCreationJobs` reads.

- [ ] **Step 1: Write the failing tests**

Append to `apps/controltower-ui/tests/test_app.py`:

```python
def test_new_project_status_reports_no_previous_project(client, tmp_path):
    parent = tmp_path / "status parent"
    parent.mkdir()
    response = client.get(
        "/api/new-project/status",
        query_string={"project_name": "Never Created", "parent_path": str(parent)},
    )
    assert response.status_code == 200
    payload = response.get_json()
    assert payload["has_previous"] is False
    assert payload["functional_status"] is None


def test_new_project_preview_allows_existing_when_flagged(client, tmp_path):
    parent = tmp_path / "existing parent"
    parent.mkdir()
    target = parent / "Existing_Project"
    target.mkdir()
    (target / "placeholder.txt").write_text("deja present", encoding="utf-8")
    rejected = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Existing Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Nouveau brief.",
        },
    )
    assert rejected.status_code == 400

    accepted = client.post(
        "/api/new-project/preview",
        json={
            "project_name": "Existing Project",
            "parent_path": str(parent),
            "project_type": "python-cli",
            "brief": "Nouveau brief.",
            "allow_existing": True,
        },
    )
    assert accepted.status_code == 200
    assert "-AllowExisting" in accepted.get_json()["command_preview"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: both new tests FAIL — `test_new_project_status_reports_no_previous_project` with a 404 (route doesn't exist), `test_new_project_preview_allows_existing_when_flagged` because the "existing/non-empty" rejection currently applies unconditionally and `-AllowExisting` is never added.

- [ ] **Step 3: Implement `allow_existing` in `validate_new_project_payload` and `build_new_project_command`**

In `apps/controltower-ui/app.py`, change:

old:
```python
def validate_new_project_payload(payload):
    name = sanitize_project_name(payload.get("project_name") or payload.get("name"))
    parent = Path(str(payload.get("parent_path") or payload.get("parent_dir") or "")).expanduser()
    brief = str(payload.get("brief") or "").strip()
    project_type = str(payload.get("project_type") or "python-basic").strip() or "python-basic"
    if project_type not in PROJECT_TYPES and project_type != "python-basic":
        project_type = "other"
    if not brief:
        raise ValueError("Brief projet obligatoire.")
    if not parent.exists() or not parent.is_dir():
        raise ValueError("Le dossier parent n'existe pas.")
    target = parent / name
    if target.exists() and any(target.iterdir()):
        raise ValueError("Le dossier projet existe deja et n'est pas vide.")
    return {
        "project_name": name,
        "parent_path": str(parent.resolve()),
        "project_type": project_type,
        "brief": brief,
        "target_project_path": str(target),
    }
```

new:
```python
def validate_new_project_payload(payload, allow_existing=False):
    name = sanitize_project_name(payload.get("project_name") or payload.get("name"))
    parent = Path(str(payload.get("parent_path") or payload.get("parent_dir") or "")).expanduser()
    brief = str(payload.get("brief") or "").strip()
    project_type = str(payload.get("project_type") or "python-basic").strip() or "python-basic"
    if project_type not in PROJECT_TYPES and project_type != "python-basic":
        project_type = "other"
    if not brief:
        raise ValueError("Brief projet obligatoire.")
    if not parent.exists() or not parent.is_dir():
        raise ValueError("Le dossier parent n'existe pas.")
    target = parent / name
    if (not allow_existing) and target.exists() and any(target.iterdir()):
        raise ValueError("Le dossier projet existe deja et n'est pas vide.")
    return {
        "project_name": name,
        "parent_path": str(parent.resolve()),
        "project_type": project_type,
        "brief": brief,
        "target_project_path": str(target),
    }
```

- [ ] **Step 4: Add the workspace-lookup helper and extend `build_new_project_command`**

In `apps/controltower-ui/app.py`, add this new function right before `build_new_project_command`:

```python
def find_latest_creation_workspace(target_project_path):
    workspace_root = ROOT / "creation_workspaces"
    if not workspace_root.exists():
        return None
    candidates = sorted(
        (p for p in workspace_root.iterdir() if p.is_dir() and (p / "creation.config.json").exists()),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for candidate in candidates:
        try:
            config = json.loads((candidate / "creation.config.json").read_text(encoding="utf-8"))
        except Exception:
            continue
        if str(config.get("target_project_path", "")) == str(target_project_path):
            return candidate
    return None
```

Then change `build_new_project_command`:

old:
```python
def build_new_project_command(payload, run_aider=False, persist_brief=False):
    data = validate_new_project_payload(payload)
    if persist_brief:
        brief_path = write_creation_brief_request(data["project_name"], data["brief"])
    else:
        brief_path = "<BRIEF_FILE_CREATED_ON_LAUNCH>"
    command = (
        'powershell -ExecutionPolicy Bypass -File "' + str(ROOT / "tools" / "Invoke-ControlTowerRun.ps1") + '" '
        '-Mode Creation -ProjectName '
        + quote_arg(data["project_name"])
        + " -ParentPath "
        + quote_arg(data["parent_path"])
        + " -ProjectType "
        + quote_arg(data["project_type"])
        + " -BriefPath "
        + quote_arg(brief_path)
        + " -WorkspaceRoot "
        + quote_arg(str(ROOT / "creation_workspaces"))
    )
    args = [
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "tools" / "Invoke-ControlTowerRun.ps1"),
        "-Mode",
        "Creation",
        "-ProjectName",
        data["project_name"],
        "-ParentPath",
        data["parent_path"],
        "-ProjectType",
        data["project_type"],
        "-BriefPath",
        brief_path,
        "-WorkspaceRoot",
        str(ROOT / "creation_workspaces"),
    ]
    if run_aider:
        command += " -RunAider"
        args.append("-RunAider")
    else:
        command += " -ValidateAfterDryRun"
        args.append("-ValidateAfterDryRun")
    return data, command, args
```

new:
```python
def build_new_project_command(payload, run_aider=False, persist_brief=False, allow_existing=False, correction_notes=""):
    data = validate_new_project_payload(payload, allow_existing=allow_existing)
    if persist_brief:
        brief_text = data["brief"]
        if allow_existing and correction_notes.strip():
            previous_workspace = find_latest_creation_workspace(data["target_project_path"])
            if previous_workspace is not None:
                previous_brief_path = previous_workspace / "project_brief.md"
                if previous_brief_path.exists():
                    brief_text = previous_brief_path.read_text(encoding="utf-8")
            brief_text = brief_text + "\n\n## Correction requise\n\n" + correction_notes.strip() + "\n"
        brief_path = write_creation_brief_request(data["project_name"], brief_text)
    else:
        brief_path = "<BRIEF_FILE_CREATED_ON_LAUNCH>"
    command = (
        'powershell -ExecutionPolicy Bypass -File "' + str(ROOT / "tools" / "Invoke-ControlTowerRun.ps1") + '" '
        '-Mode Creation -ProjectName '
        + quote_arg(data["project_name"])
        + " -ParentPath "
        + quote_arg(data["parent_path"])
        + " -ProjectType "
        + quote_arg(data["project_type"])
        + " -BriefPath "
        + quote_arg(brief_path)
        + " -WorkspaceRoot "
        + quote_arg(str(ROOT / "creation_workspaces"))
    )
    args = [
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(ROOT / "tools" / "Invoke-ControlTowerRun.ps1"),
        "-Mode",
        "Creation",
        "-ProjectName",
        data["project_name"],
        "-ParentPath",
        data["parent_path"],
        "-ProjectType",
        data["project_type"],
        "-BriefPath",
        brief_path,
        "-WorkspaceRoot",
        str(ROOT / "creation_workspaces"),
    ]
    if allow_existing:
        command += " -AllowExisting"
        args.append("-AllowExisting")
    if run_aider:
        command += " -RunAider"
        args.append("-RunAider")
    else:
        command += " -ValidateAfterDryRun"
        args.append("-ValidateAfterDryRun")
    return data, command, args
```

- [ ] **Step 5: Wire `allow_existing`/`correction_notes` through the two routes**

In `apps/controltower-ui/app.py`, change the `/api/new-project/preview` route:

old:
```python
    @app.route("/api/new-project/preview", methods=["POST"])
    def api_new_project_preview():
        payload = request.get_json(silent=True)
        if payload is None:
            return jsonify({"error": "JSON invalide."}), 400
        try:
            data, command, _args = build_new_project_command(payload, run_aider=False)
            return jsonify({"ok": True, "project": data, "command_preview": command})
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400
```

new:
```python
    @app.route("/api/new-project/preview", methods=["POST"])
    def api_new_project_preview():
        payload = request.get_json(silent=True)
        if payload is None:
            return jsonify({"error": "JSON invalide."}), 400
        try:
            data, command, _args = build_new_project_command(
                payload,
                run_aider=False,
                allow_existing=bool(payload.get("allow_existing")),
                correction_notes=str(payload.get("correction_notes") or ""),
            )
            return jsonify({"ok": True, "project": data, "command_preview": command})
        except Exception as exc:
            return jsonify({"error": str(exc)}), 400
```

Then change `create_new_project_job`:

old:
```python
def create_new_project_job(payload, confirmed=False):
    run_aider = bool(payload.get("run_aider"))
    if run_aider and not confirmed:
        raise PermissionError("Confirmation requise pour cette action.")
    data, command, args = build_new_project_command(payload, run_aider=run_aider, persist_brief=True)
```

new:
```python
def create_new_project_job(payload, confirmed=False):
    run_aider = bool(payload.get("run_aider"))
    if run_aider and not confirmed:
        raise PermissionError("Confirmation requise pour cette action.")
    data, command, args = build_new_project_command(
        payload,
        run_aider=run_aider,
        persist_brief=True,
        allow_existing=bool(payload.get("allow_existing")),
        correction_notes=str(payload.get("correction_notes") or ""),
    )
```

- [ ] **Step 6: Add the status endpoint**

In `apps/controltower-ui/app.py`, add this new route right before `/api/new-project` (find `@app.route("/api/new-project", methods=["POST"])` and insert before it):

```python
    @app.route("/api/new-project/status")
    def api_new_project_status():
        project_name = request.args.get("project_name", "").strip()
        parent_path = request.args.get("parent_path", "").strip()
        if not project_name or not parent_path:
            return jsonify({"has_previous": False, "functional_status": None, "checks": []})
        try:
            safe_name = sanitize_project_name(project_name)
        except ValueError:
            return jsonify({"has_previous": False, "functional_status": None, "checks": []})
        target = str((Path(parent_path).expanduser() / safe_name))
        workspace = find_latest_creation_workspace(target)
        if workspace is None:
            return jsonify({"has_previous": False, "functional_status": None, "checks": []})
        result_path = workspace / "validation" / "creation_result.json"
        if not result_path.exists():
            return jsonify({"has_previous": True, "functional_status": None, "checks": []})
        try:
            result = json.loads(result_path.read_text(encoding="utf-8"))
        except Exception:
            return jsonify({"has_previous": True, "functional_status": None, "checks": []})
        functional_check = result.get("functional_check") or {}
        return jsonify(
            {
                "has_previous": True,
                "functional_status": functional_check.get("status"),
                "checks": functional_check.get("checks", []),
            }
        )
```

- [ ] **Step 7: Populate `functional_check` on the creation job dict when it finishes**

The job's `output` field already contains the raw log text (including the `Functional check: ...` line from Task 3), but the UI needs the structured object. In `apps/controltower-ui/app.py`, find `run_dynamic_job` (the function used for creation jobs) and locate where it sets the job's final status after the process exits (the block that does `job["status"] = "succeeded" if return_code == 0 else "failed"`). Add a read of the workspace's `creation_result.json` right after that block, using the job's `target_project_path`.

Since `run_dynamic_job` doesn't currently know the workspace path (only `target_project_path`), add this lookup using `find_latest_creation_workspace`. Change the section of `run_dynamic_job` that finalizes the job (locate the line `job["output"] = output` inside the success path, near the end of the function) — add immediately after it:

```python
            if job.get("command") == "new_project" and job.get("target_project_path"):
                try:
                    workspace = find_latest_creation_workspace(job["target_project_path"])
                    if workspace is not None:
                        result_path = workspace / "validation" / "creation_result.json"
                        if result_path.exists():
                            creation_result = json.loads(result_path.read_text(encoding="utf-8"))
                            job["functional_check"] = creation_result.get("functional_check")
                except Exception:
                    pass
```

(Place this inside the `with JOBS_LOCK:` block where `job["output"] = output` is set, right after that line, so it's set before the lock releases.)

- [ ] **Step 8: Run the tests to verify they pass**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: all tests pass, including the two new ones from Step 1.

- [ ] **Step 9: Commit**

```bash
git add apps/controltower-ui/app.py apps/controltower-ui/tests/test_app.py
git commit -m "feat: support allow_existing/correction_notes for re-running creation"
```

---

### Task 8: "Corriger ce projet" UI flow

**Files:**
- Modify: `apps/controltower-ui/templates/index.html`
- Modify: `apps/controltower-ui/static/app.js`

**Interfaces:**
- Consumes: `GET /api/new-project/status` (Task 7), `POST /api/new-project` with `allow_existing`/`correction_notes` (Task 7).
- Produces: none consumed by other tasks — this is the final task.

- [ ] **Step 1: Add the correction notes field and button to the HTML**

In `apps/controltower-ui/templates/index.html`, change:

old:
```html
            <div id="newProjectPreview" class="preview-block"></div>
            <div class="modal-actions">
              <button id="newProjectPreviewButton" class="secondary" type="button">Dry-run</button>
              <button id="newProjectRunButton" class="danger" type="button">Lancer Aider</button>
            </div>
```

new:
```html
            <div id="newProjectPreview" class="preview-block"></div>
            <div id="newProjectCorrectionBlock" class="correction-block" hidden>
              <label>
                Notes de correction
                <textarea id="newProjectCorrectionNotes" rows="6" placeholder="Precise ce qui doit etre corrige."></textarea>
              </label>
            </div>
            <div class="modal-actions">
              <button id="newProjectPreviewButton" class="secondary" type="button">Dry-run</button>
              <button id="newProjectRunButton" class="danger" type="button">Lancer Aider</button>
              <button id="newProjectCorrectButton" class="danger" type="button" hidden>Corriger et relancer Aider</button>
            </div>
```

- [ ] **Step 2: Add minimal CSS for the correction block**

In `apps/controltower-ui/static/styles.css`, after the `.functional-summary` rules added in Task 6, add:

```css
.correction-block textarea {
  width: 100%;
  font-family: inherit;
}
```

- [ ] **Step 3: Wire the element references and status check**

In `apps/controltower-ui/static/app.js`, change the `els` object — add three lines right after the existing `newProjectPreview` line:

old:
```javascript
  newProjectPreview: document.getElementById("newProjectPreview")
};
```

new:
```javascript
  newProjectPreview: document.getElementById("newProjectPreview"),
  newProjectCorrectionBlock: document.getElementById("newProjectCorrectionBlock"),
  newProjectCorrectionNotes: document.getElementById("newProjectCorrectionNotes"),
  newProjectCorrectButton: document.getElementById("newProjectCorrectButton")
};
```

- [ ] **Step 4: Write the status-check function**

In `apps/controltower-ui/static/app.js`, add this new function right after `previewNewProject` (which ends around line 606):

```javascript
async function checkPreviousCreationStatus() {
  if (!els.newProjectName || !els.newProjectParent) return;
  const name = els.newProjectName.value.trim();
  const parent = els.newProjectParent.value.trim();
  if (!name || !parent) {
    if (els.newProjectCorrectionBlock) els.newProjectCorrectionBlock.hidden = true;
    if (els.newProjectCorrectButton) els.newProjectCorrectButton.hidden = true;
    return;
  }
  try {
    const params = new URLSearchParams({ project_name: name, parent_path: parent });
    const payload = await requestJson("/api/new-project/status?" + params.toString(), { method: "GET" });
    const shouldShowCorrection = payload.has_previous && payload.functional_status === "failed";
    if (els.newProjectCorrectionBlock) els.newProjectCorrectionBlock.hidden = !shouldShowCorrection;
    if (els.newProjectCorrectButton) els.newProjectCorrectButton.hidden = !shouldShowCorrection;
    if (shouldShowCorrection && els.newProjectCorrectionNotes && !els.newProjectCorrectionNotes.value) {
      const details = (payload.checks || [])
        .filter((c) => c.status === "failed")
        .map((c) => "- " + (c.detail || c.name))
        .join("\n");
      els.newProjectCorrectionNotes.value = details;
    }
  } catch (error) {
    if (els.newProjectCorrectionBlock) els.newProjectCorrectionBlock.hidden = true;
    if (els.newProjectCorrectButton) els.newProjectCorrectButton.hidden = true;
  }
}
```

- [ ] **Step 5: Wire the correction submit function**

In `apps/controltower-ui/static/app.js`, find `collectNewProjectPayload` (referenced by `previewNewProject`/`submitNewProject`) and add a new function right after `submitNewProject` (which ends around line 627):

```javascript
async function submitCreationCorrection() {
  try {
    const payload = {
      ...collectNewProjectPayload(true),
      allow_existing: true,
      correction_notes: els.newProjectCorrectionNotes ? els.newProjectCorrectionNotes.value : ""
    };
    const accepted = await showConfirm(
      "Corriger le projet avec Aider",
      "ControlTower va relancer Aider/Ornith sur le projet existant avec les notes de correction, puis valider a nouveau."
    );
    if (!accepted) return;
    await requestJson("/api/new-project", {
      method: "POST",
      body: JSON.stringify({ ...payload, confirmed: true })
    });
    startJobPolling();
    await refresh();
  } catch (error) {
    showError("Correction non lancee", friendlyError(error), error.message);
  }
}
```

- [ ] **Step 6: Register the event listeners**

In `apps/controltower-ui/static/app.js`, change:

old:
```javascript
if (els.newProjectBrowseParentButton) els.newProjectBrowseParentButton.addEventListener("click", browseNewProjectParent);
if (els.saveCreationParentButton) els.saveCreationParentButton.addEventListener("click", saveCreationParent);
if (els.newProjectPreviewButton) els.newProjectPreviewButton.addEventListener("click", previewNewProject);
if (els.newProjectRunButton) els.newProjectRunButton.addEventListener("click", () => submitNewProject(true));
```

new:
```javascript
if (els.newProjectBrowseParentButton) els.newProjectBrowseParentButton.addEventListener("click", browseNewProjectParent);
if (els.saveCreationParentButton) els.saveCreationParentButton.addEventListener("click", saveCreationParent);
if (els.newProjectPreviewButton) els.newProjectPreviewButton.addEventListener("click", previewNewProject);
if (els.newProjectRunButton) els.newProjectRunButton.addEventListener("click", () => submitNewProject(true));
if (els.newProjectCorrectButton) els.newProjectCorrectButton.addEventListener("click", submitCreationCorrection);
if (els.newProjectName) els.newProjectName.addEventListener("blur", checkPreviousCreationStatus);
if (els.newProjectParent) els.newProjectParent.addEventListener("blur", checkPreviousCreationStatus);
```

- [ ] **Step 7: Manual end-to-end verification**

Start the webapp, go to the Création tab, enter a project name/parent that has no previous creation — confirm the correction block/button stay hidden. This is a UI-only smoke check; full end-to-end (a real failed creation triggering the correction flow) was already exercised manually today with Neon Paddle via the equivalent PowerShell calls this feature now wraps.

- [ ] **Step 8: Run the Flask UI test suite**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: all tests pass (no backend change in this task).

- [ ] **Step 9: Commit**

```bash
git add apps/controltower-ui/templates/index.html apps/controltower-ui/static/app.js apps/controltower-ui/static/styles.css
git commit -m "feat: add Corriger ce projet flow to the creation view"
```

---

## Final verification

- [ ] `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` — all suites pass, including the two new ones (`Test-PowerShellEncodingLint.ps1` was already there; `Test-ProjectFunctionalCheck.ps1` is new from this plan).
- [ ] `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` — all tests pass.
- [ ] Manual smoke test: recreate the Neon Paddle scenario (a webapp brief that an LLM is likely to under-implement, or simply a hand-crafted broken fixture) through the real UI, end to end, and confirm the pipeline now reports `failed` instead of a false `passed`, the reason is visible in plain French without opening any file, and the "Corriger ce projet" button appears and works.
