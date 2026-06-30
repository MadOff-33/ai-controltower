param(
  [string]$MemoryRoot = "C:\AI_ControlTower\hermes_memory",

  [Parameter(Mandatory = $true)]
  [string]$RunResultPath
)

$ErrorActionPreference = "Stop"

$addScript = "C:\AI_ControlTower\tools\Add-HermesMemoryEntry.ps1"
if (-not (Test-Path -LiteralPath $addScript)) { throw "Add-HermesMemoryEntry.ps1 introuvable." }

$runPath = (Resolve-Path -LiteralPath $RunResultPath).ProviderPath
$run = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json
$status = [string]$run.status
if ([string]::IsNullOrWhiteSpace($status) -and $null -ne $run.passed) {
  $status = $(if ($run.passed) { "passed" } else { "failed" })
}
if ([string]::IsNullOrWhiteSpace($status)) { $status = "observed" }

$mode = [string]$run.mode
if ([string]::IsNullOrWhiteSpace($mode) -and $null -ne $run.ticket) { $mode = "Fix" }
if ([string]::IsNullOrWhiteSpace($mode)) { $mode = "Unknown" }

if ($status -eq "passed") {
  & $addScript -MemoryRoot $MemoryRoot -Kind "success" -Category "run_outcome" -Summary ("Run " + $mode + " valide par ControlTower.") -Source "post_run" -Confidence "medium" -Status "active" -Evidence @("Run result status: passed") -RunLog $runPath | Out-Null
} else {
  & $addScript -MemoryRoot $MemoryRoot -Kind "failure" -Category "run_outcome" -Summary ("Run " + $mode + " non valide ou en echec.") -Source "post_run" -Confidence "medium" -Status "active" -Evidence @("Run result status: " + $status) -RunLog $runPath | Out-Null
}

$unauthorized = @()
if ($null -ne $run.unauthorized_changes) { $unauthorized = @($run.unauthorized_changes) }
if ($unauthorized.Count -gt 0) {
  & $addScript -MemoryRoot $MemoryRoot -Kind "validation_rule" -Category "unauthorized_changes" -Summary "Un run doit etre rejete si des fichiers hors perimetre changent." -Source "post_run_validation" -Confidence "high" -Status "active" -Evidence @("unauthorized_changes > 0") -Lesson "Verifier les changements autorises avant de regarder les tests fonctionnels." -SuggestedActions @("Executer le validateur ControlTower approprie.", "Rejeter les sorties hors ticket ou hors reports/.") -RunLog $runPath | Out-Null
}

$ghosts = @()
if ($null -ne $run.ghost_findings) { $ghosts = @($run.ghost_findings) }
if ($ghosts.Count -gt 0) {
  & $addScript -MemoryRoot $MemoryRoot -Kind "model_behavior" -Category "ghost_facts" -Summary "Le modele peut introduire des fichiers, fonctions ou points d'entree absents du contexte." -Source "post_run_validation" -Confidence "high" -Status "active" -Evidence @("ghost_findings > 0") -Lesson "Exiger une preuve issue du contexte pour toute affirmation factuelle." -SuggestedActions @("Inclure une section Incertitudes.", "Refuser les marqueurs fantomes absents du contexte.") -RunLog $runPath | Out-Null
}

$commandResults = @()
if ($null -ne $run.command_results) { $commandResults = @($run.command_results) }
$failedCommands = @($commandResults | Where-Object { $_.exit_code -ne 0 })
if ($failedCommands.Count -gt 0) {
  & $addScript -MemoryRoot $MemoryRoot -Kind "tool_limitation" -Category "verification_command" -Summary "Une commande de verification peut echouer meme si le diff semble plausible." -Source "post_run_validation" -Confidence "medium" -Status "active" -Evidence @("failed verification commands > 0") -Lesson "Ne jamais annoncer une correction acceptee si une commande de verification echoue." -SuggestedActions @("Capturer la sortie de commande.", "Relancer apres correction du ticket ou de l'environnement.") -RunLog $runPath | Out-Null
}

Write-Host "=== Hermes updated from run ==="
Write-Host ("Run: " + $runPath)
Write-Host ("Status: " + $status)
