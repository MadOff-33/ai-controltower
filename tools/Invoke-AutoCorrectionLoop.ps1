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

  # Diagnostic progress lines are redirected to null rather than emitted via
  # Write-Host: when this script is itself invoked as `powershell -File ... |
  # Out-String` (as the interface contract and Task 3 require, and as this
  # test suite does), Windows PowerShell 5.1 merges a child process's
  # Write-Host output into the captured stdout stream, which would corrupt
  # the single JSON object this script promises to print on stdout.
  Write-Host ("=== Tentative de correction " + ($attempt + 1) + "/" + $MaxAttempts + " : " + $failedCheck.name + " dans " + $targetLabel + " ===") *> $null

  Invoke-TargetedAiderFix -ProjectPath $ProjectPath -TargetFile $targetFile -BriefText $brief -Model $Model -AiderExecutable $AiderExecutable

  $attempt++

  $recheckOutput = & powershell -ExecutionPolicy Bypass -File $functionalScript -ProjectPath $ProjectPath -ProjectType $ProjectType | Out-String
  $recheckResult = $recheckOutput | ConvertFrom-Json
  $targetCheckNowOk = @($recheckResult.checks | Where-Object { $_.name -eq $failedCheck.name -and $_.status -eq "ok" }).Count -gt 0
  $outcome = if ($targetCheckNowOk) { "fixed" } else { "not_fixed" }

  $history += [ordered]@{ attempt = $attempt; check_name = $failedCheck.name; target_file = $targetFile; outcome = $outcome }

  $contextJson = (@{ outcome = $outcome; target_file = $targetFile; attempt_number = $attempt } | ConvertTo-Json -Compress)
  # Call Add-HermesMemoryEntry.ps1 in-process via `&` (same pattern as
  # Update-HermesFromRun.ps1) rather than spawning a child `powershell -File`
  # process: routing a JSON string containing both `"` and spaces through a
  # native-process command line is unreliable on Windows (Win32 argv parsing
  # can truncate/mangle it), and staying in-process avoids that entirely.
  & (Join-Path $PSScriptRoot "Add-HermesMemoryEntry.ps1") `
    -MemoryRoot $HermesMemoryRoot -Kind "correction_attempt" -Category $failedCheck.name -Source "auto_correction_loop" `
    -Summary ("Tentative de correction automatique sur " + $failedCheck.name + " : " + $outcome) `
    -ContextJson $contextJson *> $null

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
