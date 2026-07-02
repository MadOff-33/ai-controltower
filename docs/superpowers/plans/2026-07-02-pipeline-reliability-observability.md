# Pipeline Reliability & Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close three infrastructure gaps found while creating a real project through ControlTower: PowerShell scripts silently misreading UTF-8 content, a non-hermetic Hermes-memory test dependency, and no observability into whether the configured LLM's Ollama serving setup is actually healthy.

**Architecture:** A new PowerShell lint test enforces `-Encoding UTF8` on every text read in `tools/*.ps1`; a `-HermesMemoryRoot` parameter is threaded through the full Start-Aider → Invoke-Aider*Pipeline → Invoke-ControlTowerRun chain so tests can use an isolated memory instead of the real global one; and two new observability layers (a cheap static check wired into the existing dependency panel, and an on-demand live check reusing the existing job/command system) surface model-serving health without any new UI code.

**Tech Stack:** PowerShell 5.1/7, Python 3.12 (Flask), Ollama HTTP API.

## Global Constraints

- No UI redesign and no model picker — `ollama_chat/ornith:9b` stays hardcoded elsewhere in the codebase (explicit non-goal; a future sub-project will address model selection in the UI).
- Every fix must be general-purpose: none of these changes may be tuned to make any specific project (e.g. Neon Paddle) pass — they must hold for any future creation/audit/fix request.
- No new information may be promoted as `success`/`passed` without a check that actually justifies it (anti-false-positive principle).
- Any new capability that is "configurable" must be visible through an existing UI surface if one exists (dependency panel, command/job list) rather than introducing a hidden, script-only setting.
- Backward compatibility: every new parameter's default value must reproduce today's exact current behavior — zero regression for existing callers that don't pass the new parameter.
- Test command for PowerShell suites: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` (from repo root).
- Test command for the Flask UI: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` (from repo root).

---

### Task 1: Encoding lint + fix all violations

**Files:**
- Create: `tools/tests/Test-PowerShellEncodingLint.ps1`
- Modify: `tools/tests/Invoke-ControlTowerTestSuite.ps1:8-15` (register the new suite)
- Modify (add `-Encoding UTF8` to the `Get-Content` call at the given line): `tools/Add-HermesMemoryEntry.ps1:36`, `tools/Get-HermesGuidance.ps1:24`, `tools/Invoke-AiderAuditContinuation.ps1:55`, `tools/Invoke-AiderCreationPipeline.ps1:91`, `tools/Invoke-AiderFixPipeline.ps1:21`, `tools/Invoke-ControlTowerRun.ps1:36`, `tools/Invoke-ControlTowerRun.ps1:187`, `tools/New-AiderFixTicketFromReport.ps1:38`, `tools/New-AuditConsolidatedReport.ps1:37`, `tools/New-AuditConsolidatedReport.ps1:53`, `tools/New-AuditWorkspace.ps1:18`, `tools/New-ContextPack.ps1:23`, `tools/New-ContextPack.ps1:35`, `tools/New-ContextPack.ps1:53`, `tools/New-ContextPack.ps1:109`, `tools/New-ContextPack.ps1:124`, `tools/New-FixContextPack.ps1:27`, `tools/New-FixContextPack.ps1:61`, `tools/New-FixContextPack.ps1:87`, `tools/New-ProjectInventory.ps1:16`, `tools/Start-AiderCreation.ps1:24`, `tools/Start-AiderFix.ps1:39`, `tools/Test-AiderCreation.ps1:81`, `tools/Test-AiderCreation.ps1:87`, `tools/Test-AiderFix.ps1:28`, `tools/Test-AiderFix.ps1:57`, `tools/Test-AiderFix.ps1:93`, `tools/Test-AiderFix.ps1:101`, `tools/Test-AiderOutput.ps1:88`, `tools/Test-AiderOutput.ps1:135`, `tools/Test-AiderOutput.ps1:140`, `tools/Test-AiderOutput.ps1:161`, `tools/Update-HermesFromRun.ps1:14`

**Interfaces:**
- Produces: `tools/tests/Test-PowerShellEncodingLint.ps1` — a standalone script, exit code 0 if zero violations, non-zero (via `throw`) otherwise. No functions are exported for other tasks to consume; later tasks in this plan only need it to keep passing.

- [ ] **Step 1: Write the lint script**

Create `tools/tests/Test-PowerShellEncodingLint.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$Root = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$toolsDir = Join-Path $Root "tools"
$testsDir = Join-Path $toolsDir "tests"

Write-Host "=== PowerShell encoding lint ==="

$files = Get-ChildItem -LiteralPath $toolsDir -Filter "*.ps1" -Recurse -File | Where-Object {
  -not $_.FullName.StartsWith($testsDir, [System.StringComparison]::OrdinalIgnoreCase)
}

$violations = @()
foreach ($file in $files) {
  $lineNumber = 0
  foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
    $lineNumber++
    if ($line -notmatch "Get-Content") { continue }
    if ($line -match "[\`"']\s*Get-Content") { continue }
    if ($line -match "-Encoding") { continue }
    $relative = $file.FullName.Substring($Root.Length + 1)
    $violations += ($relative + ":" + $lineNumber)
  }
}

if ($violations.Count -gt 0) {
  Write-Host "Violations (Get-Content without -Encoding):"
  $violations | ForEach-Object { Write-Host ("- " + $_) }
  throw ($violations.Count.ToString() + " Get-Content call(s) missing -Encoding in tools/*.ps1 (excluding tools/tests/).")
}

Write-Host "Encoding lint: 0 violations."
```

- [ ] **Step 2: Run the lint to see the current 33 violations**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-PowerShellEncodingLint.ps1`

Expected: FAILS, throws `"33 Get-Content call(s) missing -Encoding..."`, and the printed violation list matches exactly the 33 `file:line` pairs listed in this task's **Files** section above (verify the printed list against that section — if it doesn't match exactly, the regex in Step 1 needs adjustment before continuing).

- [ ] **Step 3: Fix all 33 violations**

For each `file:line` below, replace the exact `old` line with the exact `new` line (only the `-Encoding UTF8` addition changes; nothing else on the line changes):

`tools/Add-HermesMemoryEntry.ps1:36`
old: `    foreach ($line in (Get-Content -LiteralPath $EntriesPath)) {`
new: `    foreach ($line in (Get-Content -LiteralPath $EntriesPath -Encoding UTF8)) {`

`tools/Get-HermesGuidance.ps1:24`
old: `  foreach ($line in (Get-Content -LiteralPath $entries)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $entries -Encoding UTF8)) {`

`tools/Invoke-AiderAuditContinuation.ps1:55`
old: `$previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw | ConvertFrom-Json`
new: `$previousManifest = Get-Content -LiteralPath $previousManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Invoke-AiderCreationPipeline.ps1:91`
old: `$config = Get-Content -LiteralPath (Join-Path $workspace "creation.config.json") -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath (Join-Path $workspace "creation.config.json") -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Invoke-AiderFixPipeline.ps1:21`
old: `  foreach ($line in (Get-Content -LiteralPath $Path)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {`

`tools/Invoke-ControlTowerRun.ps1:36`
old: `  $pipelineResult = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json`
new: `  $pipelineResult = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Invoke-ControlTowerRun.ps1:187`
old: `    $config = Get-Content -LiteralPath (Join-Path $workspace "creation.config.json") -Raw | ConvertFrom-Json`
new: `    $config = Get-Content -LiteralPath (Join-Path $workspace "creation.config.json") -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/New-AiderFixTicketFromReport.ps1:38`
old: `$reportText = Get-Content -LiteralPath $report -Raw`
new: `$reportText = Get-Content -LiteralPath $report -Raw -Encoding UTF8`

`tools/New-AuditConsolidatedReport.ps1:37`
old: `$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/New-AuditConsolidatedReport.ps1:53`
old: `  $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json`
new: `  $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/New-AuditWorkspace.ps1:18`
old: `  $lines = Get-Content -LiteralPath $Path`
new: `  $lines = Get-Content -LiteralPath $Path -Encoding UTF8`

`tools/New-ContextPack.ps1:23`
old: `  foreach ($line in (Get-Content -LiteralPath $Path)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {`

`tools/New-ContextPack.ps1:35`
old: `  $lines = Get-Content -LiteralPath $Path`
new: `  $lines = Get-Content -LiteralPath $Path -Encoding UTF8`

`tools/New-ContextPack.ps1:53`
old: `$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/New-ContextPack.ps1:109`
old: `  (Get-Content -LiteralPath (Join-Path $workspace "inventory\summary.md") -Raw),`
new: `  (Get-Content -LiteralPath (Join-Path $workspace "inventory\summary.md") -Raw -Encoding UTF8),`

`tools/New-ContextPack.ps1:124`
old: `  $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue`
new: `  $content = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue`

`tools/New-FixContextPack.ps1:27`
old: `  foreach ($line in (Get-Content -LiteralPath $Path)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {`

`tools/New-FixContextPack.ps1:61`
old: `$ticketText = Get-Content -LiteralPath $ticket -Raw`
new: `$ticketText = Get-Content -LiteralPath $ticket -Raw -Encoding UTF8`

`tools/New-FixContextPack.ps1:87`
old: `  $content = Get-Content -LiteralPath $absolute -Raw`
new: `  $content = Get-Content -LiteralPath $absolute -Raw -Encoding UTF8`

`tools/New-ProjectInventory.ps1:16`
old: `$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Start-AiderCreation.ps1:24`
old: `$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Start-AiderFix.ps1:39`
old: `  foreach ($line in (Get-Content -LiteralPath $Path)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {`

`tools/Test-AiderCreation.ps1:81`
old: `$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Test-AiderCreation.ps1:87`
old: `$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json`
new: `$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Test-AiderFix.ps1:28`
old: `  foreach ($line in (Get-Content -LiteralPath $Path)) {`
new: `  foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {`

`tools/Test-AiderFix.ps1:57`
old: `$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json`
new: `$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Test-AiderFix.ps1:93`
old: `$contextText = Get-Content -LiteralPath $contextPack -Raw`
new: `$contextText = Get-Content -LiteralPath $contextPack -Raw -Encoding UTF8`

`tools/Test-AiderFix.ps1:101`
old: `  $text = Get-Content -LiteralPath $absolute -Raw`
new: `  $text = Get-Content -LiteralPath $absolute -Raw -Encoding UTF8`

`tools/Test-AiderOutput.ps1:88`
old: `$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json`
new: `$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Test-AiderOutput.ps1:135`
old: `  $contextManifest = Get-Content -LiteralPath $contextManifestPath -Raw | ConvertFrom-Json`
new: `  $contextManifest = Get-Content -LiteralPath $contextManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Test-AiderOutput.ps1:140`
old: `    $snapshotRoot = (Get-Content -LiteralPath $configPathForSnapshot -Raw | ConvertFrom-Json).snapshot_path`
new: `    $snapshotRoot = (Get-Content -LiteralPath $configPathForSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json).snapshot_path`

`tools/Test-AiderOutput.ps1:161`
old: `  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json`
new: `  $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json`

`tools/Update-HermesFromRun.ps1:14`
old: `$run = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json`
new: `$run = Get-Content -LiteralPath $runPath -Raw -Encoding UTF8 | ConvertFrom-Json`

- [ ] **Step 4: Run the lint again to confirm 0 violations**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-PowerShellEncodingLint.ps1`

Expected: `Encoding lint: 0 violations.`

- [ ] **Step 5: Register the lint in the test suite**

In `tools/tests/Invoke-ControlTowerTestSuite.ps1`, change:

```powershell
$Suites = @(
  "Test-AiderReliabilityLayer.ps1",
  "Test-AiderFixReliability.ps1",
  "Test-AiderCreationReliability.ps1",
  "Test-ControlTowerOrchestrator.ps1",
  "Test-HermesMemory.ps1",
  "Test-ControlTowerUI.ps1",
  "Test-ControlTowerRelease.ps1"
)
```

to:

```powershell
$Suites = @(
  "Test-PowerShellEncodingLint.ps1",
  "Test-AiderReliabilityLayer.ps1",
  "Test-AiderFixReliability.ps1",
  "Test-AiderCreationReliability.ps1",
  "Test-ControlTowerOrchestrator.ps1",
  "Test-HermesMemory.ps1",
  "Test-ControlTowerUI.ps1",
  "Test-ControlTowerRelease.ps1"
)
```

- [ ] **Step 6: Commit**

```bash
git add tools/tests/Test-PowerShellEncodingLint.ps1 tools/tests/Invoke-ControlTowerTestSuite.ps1 tools/Add-HermesMemoryEntry.ps1 tools/Get-HermesGuidance.ps1 tools/Invoke-AiderAuditContinuation.ps1 tools/Invoke-AiderCreationPipeline.ps1 tools/Invoke-AiderFixPipeline.ps1 tools/Invoke-ControlTowerRun.ps1 tools/New-AiderFixTicketFromReport.ps1 tools/New-AuditConsolidatedReport.ps1 tools/New-AuditWorkspace.ps1 tools/New-ContextPack.ps1 tools/New-FixContextPack.ps1 tools/New-ProjectInventory.ps1 tools/Start-AiderCreation.ps1 tools/Start-AiderFix.ps1 tools/Test-AiderCreation.ps1 tools/Test-AiderFix.ps1 tools/Test-AiderOutput.ps1 tools/Update-HermesFromRun.ps1
git commit -m "fix: force UTF-8 on all remaining PowerShell text reads, add permanent lint"
```

---

### Task 2: `-HermesMemoryRoot` configurable end to end

**Files:**
- Modify: `tools/Start-AiderAudit.ps1:1-14` (param block), `:49` (hardcoded path)
- Modify: `tools/Start-AiderCreation.ps1:1-7` (param block), `:54` (hardcoded path)
- Modify: `tools/Start-AiderFix.ps1:1-13` (param block), `:75` (hardcoded path)
- Modify: `tools/Invoke-AiderAuditPipeline.ps1:1-14` (param block), `:87-93` (`$startArgs`)
- Modify: `tools/Invoke-AiderCreationPipeline.ps1:1-18` (param block), `:71-75` (`$startArgs`)
- Modify: `tools/Invoke-AiderFixPipeline.ps1:1-12` (param block), `:47-53` (`$startArgs`)
- Modify: `tools/Invoke-ControlTowerRun.ps1:122-134` (`$auditArgs`), `:147-155` (`$fixArgs`), `:169-185` (`$creationArgs`)

**Interfaces:**
- Produces: `Start-AiderAudit.ps1`, `Start-AiderCreation.ps1`, `Start-AiderFix.ps1` each accept `-HermesMemoryRoot <path>` (default: `(Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory")`, i.e. today's hardcoded value) and read `guidance_cache.md` from `Join-Path $HermesMemoryRoot "central\guidance_cache.md"` instead of a hardcoded path.
- Consumes (Task 3 depends on this): the same `-HermesMemoryRoot` parameter, now present on `Invoke-AiderAuditPipeline.ps1`, `Invoke-AiderCreationPipeline.ps1`, `Invoke-AiderFixPipeline.ps1`, and reaching `Start-AiderAudit.ps1`/`Start-AiderCreation.ps1`/`Start-AiderFix.ps1` when passed through.

- [ ] **Step 1: Add the parameter and fix the hardcoded path in the three `Start-Aider*.ps1` scripts**

In `tools/Start-AiderAudit.ps1`, change the param block (lines 1-14):

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$LotName,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath,

  [string]$ReportName = "",
  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$DryRun
)
```

Then change line 49 (unchanged elsewhere in the file):
old: `$hermesText = Get-OptionalText -Path (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory\central\guidance_cache.md")`
new: `$hermesText = Get-OptionalText -Path (Join-Path $HermesMemoryRoot "central\guidance_cache.md")`

In `tools/Start-AiderCreation.ps1`, change the param block (lines 1-7):

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$DryRun
)
```

Then change line 54:
old: `$hermesText = Get-OptionalText -Path (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory\central\guidance_cache.md")`
new: `$hermesText = Get-OptionalText -Path (Join-Path $HermesMemoryRoot "central\guidance_cache.md")`

In `tools/Start-AiderFix.ps1`, change the param block (lines 1-13):

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath,

  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$DryRun
)
```

Then change line 75:
old: `$hermesText = Get-OptionalText -Path (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory\central\guidance_cache.md")`
new: `$hermesText = Get-OptionalText -Path (Join-Path $HermesMemoryRoot "central\guidance_cache.md")`

- [ ] **Step 2: Thread the parameter through the three pipeline scripts**

In `tools/Invoke-AiderAuditPipeline.ps1`, change the param block (lines 1-14):

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectPath,

  [string]$WorkspaceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "audits"),
  [string]$AuditName = "",
  [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) "templates\audit_profiles\python-basic.yaml"),
  [string]$LotName = "lot1_config",
  [string]$PromptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "prompts\audit\lot1_config.md"),
  [int]$MaxChars = 0,
  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun
)
```

Then change the `$startArgs` block (lines 87-92):

```powershell
$startArgs = @{
  WorkspacePath = $workspace
  LotName = $safeLot
  ContextPackPath = $contextPack
  Model = $Model
  HermesMemoryRoot = $HermesMemoryRoot
}
```

In `tools/Invoke-AiderCreationPipeline.ps1`, change the param block (lines 1-18):

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string]$ProjectName,

  [Parameter(Mandatory = $true)]
  [string]$ParentPath,

  [string]$Brief = "",
  [string]$BriefPath = "",

  [string]$ProjectType = "python-basic",
  [string]$WorkspaceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "creation_workspaces"),
  [string]$PromptPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "prompts\creation\new_project.md"),
  [string]$Model = "ollama_chat/ornith:9b",
  [string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory"),
  [switch]$RunAider,
  [switch]$ValidateAfterDryRun,
  [switch]$AllowExisting
)
```

Then change the `$startArgs` block (lines 71-75):

```powershell
$startArgs = @{
  WorkspacePath = $workspace
  Model = $Model
  HermesMemoryRoot = $HermesMemoryRoot
}
```

In `tools/Invoke-AiderFixPipeline.ps1`, change the param block (lines 1-12):

```powershell
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
```

Then change the `$startArgs` block (lines 47-52):

```powershell
$startArgs = @{
  WorkspacePath = $workspace
  TicketPath = $ticket
  ContextPackPath = $pack
  Model = $Model
  HermesMemoryRoot = $HermesMemoryRoot
}
```

- [ ] **Step 3: Pass it from `Invoke-ControlTowerRun.ps1`**

`Invoke-ControlTowerRun.ps1` already has `-HermesMemoryRoot` as a top-level parameter (line 20). Add `HermesMemoryRoot = $HermesMemoryRoot` to each of the three args dictionaries:

In the `$auditArgs` block (lines 122-130), change:

```powershell
    $auditArgs = @{
      ProjectPath = $ProjectPath
      WorkspaceRoot = $WorkspaceRoot
      AuditName = $AuditName
      ProfilePath = $ProfilePath
      LotName = $LotName
      PromptPath = $PromptPath
      Model = $Model
      HermesMemoryRoot = $HermesMemoryRoot
    }
```

In the `$fixArgs` block (lines 147-151), change:

```powershell
    $fixArgs = @{
      WorkspacePath = $workspace
      TicketPath = $ticket
      Model = $Model
      HermesMemoryRoot = $HermesMemoryRoot
    }
```

In the `$creationArgs` block (lines 169-176), change:

```powershell
    $creationArgs = @{
      ProjectName = $ProjectName
      ParentPath = $ParentPath
      ProjectType = $ProjectType
      WorkspaceRoot = $WorkspaceRoot
      PromptPath = $PromptPath
      Model = $Model
      HermesMemoryRoot = $HermesMemoryRoot
    }
```

- [ ] **Step 4: Verify no regression**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1 -Pattern "Test-ControlTowerOrchestrator.ps1"`

Expected: exit 0 (this suite exercises `Invoke-AiderAuditPipeline.ps1` end to end in dry-run mode and would fail if the new parameter broke argument passing).

- [ ] **Step 5: Verify the new parameter actually changes behavior**

Run (from repo root, using a scratch Hermes root that has no guidance content):

```bash
powershell -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Path 'C:\AI_ControlTower\hermes_lab\verify_hermes_param\hermes_memory\central' -Force | Out-Null; [System.IO.File]::WriteAllText('C:\AI_ControlTower\hermes_lab\verify_hermes_param\hermes_memory\central\guidance_cache.md', '# Hermes central guidance' + [Environment]::NewLine + [Environment]::NewLine + 'MARKER_FOR_STEP_5_VERIFICATION', (New-Object System.Text.UTF8Encoding($false)))"
```

Then run `tools/Start-AiderCreation.ps1` in dry-run mode against any existing creation workspace with `-HermesMemoryRoot 'C:\AI_ControlTower\hermes_lab\verify_hermes_param\hermes_memory'`, and confirm the generated `prompts\creation_aider_message.md` contains `MARKER_FOR_STEP_5_VERIFICATION` instead of whatever the real global guidance currently contains. Clean up `C:\AI_ControlTower\hermes_lab\verify_hermes_param` afterward.

Expected: the marker text appears in the message, proving the parameter is actually being read and not silently ignored.

- [ ] **Step 6: Commit**

```bash
git add tools/Start-AiderAudit.ps1 tools/Start-AiderCreation.ps1 tools/Start-AiderFix.ps1 tools/Invoke-AiderAuditPipeline.ps1 tools/Invoke-AiderCreationPipeline.ps1 tools/Invoke-AiderFixPipeline.ps1 tools/Invoke-ControlTowerRun.ps1
git commit -m "feat: thread -HermesMemoryRoot end to end through audit/fix/creation pipelines"
```

---

### Task 3: Hermetic reliability tests

**Files:**
- Modify: `tools/tests/Test-AiderCreationReliability.ps1:52-59` (pipeline call), `:79` (assertion)
- Modify: `tools/tests/Test-AiderReliabilityLayer.ps1:147` (Start-AiderAudit call), `:150` (assertion)
- Modify: `tools/tests/Test-AiderFixReliability.ps1:116` (Start-AiderFix call), `:122` (assertion)

**Interfaces:**
- Consumes: `tools/Initialize-HermesMemory.ps1 -MemoryRoot <path>`, `tools/Add-HermesMemoryEntry.ps1 -MemoryRoot <path> -Kind <string> -Category <string> -Summary <string> -Source <string>`, `tools/Get-HermesGuidance.ps1 -MemoryRoot <path>` (all pre-existing, unchanged), and the `-HermesMemoryRoot` parameter added to `Invoke-AiderCreationPipeline.ps1`/`Start-AiderAudit.ps1`/`Start-AiderFix.ps1` in Task 2.
- Produces: none consumed by later tasks — this task only makes the 3 reliability suites hermetic.

- [ ] **Step 1: Seed an isolated Hermes fixture in `Test-AiderCreationReliability.ps1`**

In `tools/tests/Test-AiderCreationReliability.ps1`, insert this block immediately before the `& (Join-Path $Root "tools\Invoke-AiderCreationPipeline.ps1")` call (currently at line 52):

```powershell
$hermesFixture = Join-Path $lab "hermes_memory"
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null
& (Join-Path $Root "tools\Add-HermesMemoryEntry.ps1") -MemoryRoot $hermesFixture -Kind "test" -Category "fixture" -Summary "MARKER_CREATION_RELIABILITY_TEST" -Source "test" | Out-Null
& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $hermesFixture | Out-Null
```

Then change the pipeline call (currently lines 52-59) from:

```powershell
& (Join-Path $Root "tools\Invoke-AiderCreationPipeline.ps1") `
  -ProjectName "Demo Creation" `
  -ParentPath $parent `
  -BriefPath $briefPath `
  -Brief "Créer une petite CLI Python qui additionne deux nombres avec un README et un test simple." `
  -ProjectType "python-cli" `
  -WorkspaceRoot $workspaces `
  -ValidateAfterDryRun
```

to:

```powershell
& (Join-Path $Root "tools\Invoke-AiderCreationPipeline.ps1") `
  -ProjectName "Demo Creation" `
  -ParentPath $parent `
  -BriefPath $briefPath `
  -Brief "Créer une petite CLI Python qui additionne deux nombres avec un README et un test simple." `
  -ProjectType "python-cli" `
  -WorkspaceRoot $workspaces `
  -HermesMemoryRoot $hermesFixture `
  -ValidateAfterDryRun
```

Then change the assertion at line 79:
old: `Assert-True -Condition ($creationMessage.Contains("Hermes central guidance")) -Message "Creation message should include Hermes guidance."`
new: `Assert-True -Condition ($creationMessage.Contains("MARKER_CREATION_RELIABILITY_TEST")) -Message "Creation message should include the seeded Hermes guidance fixture."`

- [ ] **Step 2: Run it in isolation to confirm it's now deterministic**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-AiderCreationReliability.ps1`

Expected: `All Aider creation reliability tests passed.` — and this must now hold true even if you temporarily rename/empty the real `hermes_memory/central/guidance_cache.md` (it no longer depends on it).

- [ ] **Step 3: Seed an isolated Hermes fixture in `Test-AiderReliabilityLayer.ps1`**

In `tools/tests/Test-AiderReliabilityLayer.ps1`, insert this block immediately before the `& (Join-Path $Root "tools\Start-AiderAudit.ps1")` call (currently at line 147):

```powershell
$hermesFixture = Join-Path $testRoot "hermes_memory"
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null
& (Join-Path $Root "tools\Add-HermesMemoryEntry.ps1") -MemoryRoot $hermesFixture -Kind "test" -Category "fixture" -Summary "MARKER_AUDIT_RELIABILITY_TEST" -Source "test" | Out-Null
& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $hermesFixture | Out-Null
```

Then change line 147:
old: `& (Join-Path $Root "tools\Start-AiderAudit.ps1") -WorkspacePath $workspace -LotName "lot1_config" -ContextPackPath $pack -DryRun | Out-Null`
new: `& (Join-Path $Root "tools\Start-AiderAudit.ps1") -WorkspacePath $workspace -LotName "lot1_config" -ContextPackPath $pack -HermesMemoryRoot $hermesFixture -DryRun | Out-Null`

Then change the assertion at line 150:
old: `Assert-True -Condition ($auditMessage.Contains("Hermes central guidance")) -Message "Audit message should include Hermes guidance."`
new: `Assert-True -Condition ($auditMessage.Contains("MARKER_AUDIT_RELIABILITY_TEST")) -Message "Audit message should include the seeded Hermes guidance fixture."`

- [ ] **Step 4: Run it in isolation**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-AiderReliabilityLayer.ps1`

Expected: passes (script prints its own step-by-step confirmations and does not throw).

- [ ] **Step 5: Seed an isolated Hermes fixture in `Test-AiderFixReliability.ps1`**

In `tools/tests/Test-AiderFixReliability.ps1`, insert this block immediately before the `& (Join-Path $Root "tools\Start-AiderFix.ps1")` call (currently at line 116):

```powershell
$hermesFixture = Join-Path $testRoot "hermes_memory"
& (Join-Path $Root "tools\Initialize-HermesMemory.ps1") -MemoryRoot $hermesFixture | Out-Null
& (Join-Path $Root "tools\Add-HermesMemoryEntry.ps1") -MemoryRoot $hermesFixture -Kind "test" -Category "fixture" -Summary "MARKER_FIX_RELIABILITY_TEST" -Source "test" | Out-Null
& (Join-Path $Root "tools\Get-HermesGuidance.ps1") -MemoryRoot $hermesFixture | Out-Null
```

Then change line 116:
old: `& (Join-Path $Root "tools\Start-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack -DryRun | Out-Null`
new: `& (Join-Path $Root "tools\Start-AiderFix.ps1") -WorkspacePath $workspace -TicketPath $ticket -ContextPackPath $pack -HermesMemoryRoot $hermesFixture -DryRun | Out-Null`

Then change the assertion at line 122:
old: `Assert-True -Condition ($fixMessage.Contains("Hermes central guidance")) -Message "Fix message should include Hermes guidance."`
new: `Assert-True -Condition ($fixMessage.Contains("MARKER_FIX_RELIABILITY_TEST")) -Message "Fix message should include the seeded Hermes guidance fixture."`

- [ ] **Step 6: Run the full suite to confirm nothing else regressed**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1`

Expected: `=== ControlTower test suite passed ===` with all suites listed at exit code 0.

- [ ] **Step 7: Commit**

```bash
git add tools/tests/Test-AiderCreationReliability.ps1 tools/tests/Test-AiderReliabilityLayer.ps1 tools/tests/Test-AiderFixReliability.ps1
git commit -m "test: make Hermes-dependent reliability suites hermetic with isolated fixtures"
```

---

### Task 4: Static model-serving health check (automatic, in the existing dependency panel)

**Files:**
- Modify: `tools/Test-ControlTowerDependencies.ps1`
- Modify: `tools/tests/Test-ControlTowerUI.ps1:179-182`

**Interfaces:**
- Produces: `Test-ControlTowerDependencies.ps1`'s JSON output gains a `serving_health` key: `{ "name": <model>, "status": "ok"|"warning"|"unknown", "message": <string> }`. This is already surfaced automatically to the webapp UI, since `apps/controltower-ui/app.py`'s `get_dependency_info()` calls this script on every `GET /api/state` and returns its full JSON under `dependencies` — no Python/UI change needed for this task.

- [ ] **Step 1: Add the `Test-OllamaServingHealth` function**

In `tools/Test-ControlTowerDependencies.ps1`, after the existing `Test-OllamaModel` function (currently ending at line 30), insert:

```powershell
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
```

- [ ] **Step 2: Wire it into the result**

In `tools/Test-ControlTowerDependencies.ps1`, in the `$result` block (currently lines 36-58), add a new key right after `ornith`:

old:
```powershell
  ornith = Test-OllamaModel -ModelName "ornith:9b"
  hermes = [ordered]@{
```

new:
```powershell
  ornith = Test-OllamaModel -ModelName "ornith:9b"
  serving_health = Test-OllamaServingHealth -ModelName "ornith:9b"
  hermes = [ordered]@{
```

- [ ] **Step 3: Verify manually**

Run: `powershell -ExecutionPolicy Bypass -File tools\Test-ControlTowerDependencies.ps1 -ProjectPath "C:\AI_ControlTower" -HermesMemoryRoot "C:\AI_ControlTower\hermes_memory"`

Expected: JSON output includes `"serving_health": { "name": "ornith:9b", "status": "ok", "message": "..." }` (status `"ok"` on this machine, per the live investigation done during brainstorming — `RENDERER ornith` is present).

- [ ] **Step 4: Extend the existing UI dependency test**

In `tools/tests/Test-ControlTowerUI.ps1`, after line 182 (`Assert-True -Condition ($deps.hermes.available -eq $true) -Message "Hermes should be initialized."`), add:

```powershell
Assert-True -Condition ($deps.serving_health.status -in @("ok", "warning", "unknown")) -Message "Serving health status missing or invalid."
Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($deps.serving_health.message)) -Message "Serving health message should not be empty."
```

- [ ] **Step 5: Run the UI test suite**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-ControlTowerUI.ps1`

Expected: passes through to completion without throwing.

- [ ] **Step 6: Commit**

```bash
git add tools/Test-ControlTowerDependencies.ps1 tools/tests/Test-ControlTowerUI.ps1
git commit -m "feat: surface Ollama serving-template health in the existing dependency check"
```

---

### Task 5: On-demand live model health check (new command, reuses existing job UI)

**Files:**
- Create: `tools/Test-ModelServingHealth.ps1`
- Modify: `apps/controltower-ui/app.py` (add a `model_health_check` entry to `build_commands()`)
- Modify: `apps/controltower-ui/tests/test_app.py`
- Modify: `tools/tests/Test-ControlTowerUI.ps1:190-198` (extend the commands assertions)

**Interfaces:**
- Consumes: none from earlier tasks in this plan.
- Produces: `tools/Test-ModelServingHealth.ps1 -ModelName <string> -OllamaHost <string> -TimeoutSeconds <int>` — prints a JSON object `{ checked_at, model, status: "ok"|"failed", message }` to stdout and exits 0 on `"ok"`, 1 otherwise. `apps/controltower-ui/app.py`'s `build_commands()` gains key `"model_health_check"` with the same shape as every other entry (`label`, `group`, `dangerous`, `template`, `description`, `command`, `args`).

- [ ] **Step 1: Write `Test-ModelServingHealth.ps1`**

Create `tools/Test-ModelServingHealth.ps1`:

```powershell
param(
  [string]$ModelName = "ornith:9b",
  [string]$OllamaHost = "http://localhost:11434",
  [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Test-RepetitionLoop {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $chunkLength = 15
  if ($Text.Length -lt $chunkLength) { return $false }
  for ($i = 0; $i -le ($Text.Length - $chunkLength); $i++) {
    $chunk = $Text.Substring($i, $chunkLength)
    $occurrences = ([regex]::Matches($Text, [regex]::Escape($chunk))).Count
    if ($occurrences -ge 3) { return $true }
  }
  return $false
}

$body = @{
  model = $ModelName
  messages = @(
    @{ role = "system"; content = "Tu es un assistant de code concis." },
    @{ role = "user"; content = "Ecris juste une fonction Python add(a, b) qui retourne a + b, sans explication." }
  )
  stream = $false
} | ConvertTo-Json -Depth 6

$result = [ordered]@{
  checked_at = (Get-Date).ToString("o")
  model = $ModelName
  status = "unknown"
  message = ""
}

try {
  $response = Invoke-RestMethod -Uri ($OllamaHost + "/api/chat") -Method Post -Body $body -ContentType "application/json; charset=utf-8" -TimeoutSec $TimeoutSeconds
  $content = [string]$response.message.content
  $doneReason = [string]$response.done_reason
  $looping = Test-RepetitionLoop -Text $content
  if ($looping) {
    $result.status = "failed"
    $result.message = "Reponse du modele '" + $ModelName + "' detectee en boucle de repetition."
  } elseif ($doneReason -ne "stop") {
    $result.status = "failed"
    $result.message = "Le modele '" + $ModelName + "' n'a pas termine proprement (done_reason=" + $doneReason + "), signe possible de derive."
  } elseif ([string]::IsNullOrWhiteSpace($content)) {
    $result.status = "failed"
    $result.message = "Le modele '" + $ModelName + "' a renvoye une reponse vide."
  } else {
    $result.status = "ok"
    $result.message = "Modele '" + $ModelName + "' repond correctement, sans boucle de repetition."
  }
} catch {
  $result.status = "failed"
  $result.message = "Echec de l'appel au modele '" + $ModelName + "': " + $_.Exception.Message
}

$result | ConvertTo-Json -Depth 6
if ($result.status -ne "ok") { exit 1 }
exit 0
```

- [ ] **Step 2: Run it manually to confirm it passes on this machine**

Run: `powershell -ExecutionPolicy Bypass -File tools\Test-ModelServingHealth.ps1 -ModelName "ornith:9b"`

Expected: prints JSON with `"status": "ok"`, exits 0 (matches the live check already performed manually during brainstorming, which found no repetition loop and `done_reason: "stop"`).

- [ ] **Step 3: Add the webapp command entry**

In `apps/controltower-ui/app.py`, inside `build_commands()`, add a new entry immediately after the existing `"hermes_guidance"` entry (before `"git_status"`):

```python
        "model_health_check": {
            "label": "Verifier le service modele",
            "group": "Modele",
            "dangerous": False,
            "template": False,
            "description": "Envoie un prompt de controle au modele configure et verifie l'absence de boucle de repetition ou de reponse tronquee.",
            "command": 'powershell -ExecutionPolicy Bypass -File "' + str(ROOT / "tools" / "Test-ModelServingHealth.ps1") + '"',
            "args": ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "tools" / "Test-ModelServingHealth.ps1")],
        },
```

- [ ] **Step 4: Write a failing test for the new command's presence**

Append to `apps/controltower-ui/tests/test_app.py`:

```python
def test_state_endpoint_exposes_model_health_check_command(client):
    state = client.get("/api/state")
    assert state.status_code == 200
    payload = state.get_json()
    assert "model_health_check" in payload["commands"]
    command = payload["commands"]["model_health_check"]
    assert command["dangerous"] is False
    assert "Test-ModelServingHealth.ps1" in command["command"]
```

- [ ] **Step 5: Run the test to verify it fails, then passes after Step 3**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui`

Expected: if run before Step 3's edit, `test_state_endpoint_exposes_model_health_check_command` FAILS with a `KeyError`/assertion failure on `"model_health_check" in payload["commands"]`. After Step 3's edit is in place, re-run and expect all tests (11/11) to PASS.

- [ ] **Step 6: Extend the PowerShell self-test command coverage**

In `tools/tests/Test-ControlTowerUI.ps1`, after line 194 (`Assert-True -Condition ($selfTest.commands.aider_manual.command.Contains("ollama_chat/ornith:9b")) -Message "Manual Aider command missing Ornith."`), add:

```powershell
Assert-True -Condition ($selfTest.commands.PSObject.Properties.Name -contains "model_health_check") -Message "Model health check command missing."
Assert-True -Condition ($selfTest.commands.model_health_check.dangerous -eq $false) -Message "Model health check should not require confirmation."
```

- [ ] **Step 7: Run the UI test suite**

Run: `powershell -ExecutionPolicy Bypass -File tools\tests\Test-ControlTowerUI.ps1`

Expected: passes through to completion without throwing (this suite already runs the pytest suite from Step 5 internally at its own line ~200-202, plus the PowerShell-level self-test assertions).

- [ ] **Step 8: Commit**

```bash
git add tools/Test-ModelServingHealth.ps1 apps/controltower-ui/app.py apps/controltower-ui/tests/test_app.py tools/tests/Test-ControlTowerUI.ps1
git commit -m "feat: add on-demand live model-serving health check as a webapp command"
```

---

## Final verification

- [ ] Run the full PowerShell suite from repo root: `powershell -ExecutionPolicy Bypass -File tools\tests\Invoke-ControlTowerTestSuite.ps1` — all 8 suites pass (including the new `Test-PowerShellEncodingLint.ps1`), and this must hold true regardless of the current contents of the real global `hermes_memory/central/guidance_cache.md`.
- [ ] Run the Flask UI suite: `powershell -ExecutionPolicy Bypass -File tools\tests\run_pytest.ps1 -Path apps\controltower-ui` — all tests pass, including the new `model_health_check` command coverage.
- [ ] `git status` — working tree clean, no stray files.
