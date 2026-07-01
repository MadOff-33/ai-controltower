param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath,

  [string]$Model = "ollama_chat/ornith:9b",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Quote-Arg {
  param([string]$Value)
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Enable-AiderUtf8Environment {
  $script:PreviousPythonUtf8 = $env:PYTHONUTF8
  $script:PreviousPythonIoEncoding = $env:PYTHONIOENCODING
  $script:PreviousPythonLegacyWindowsStdio = $env:PYTHONLEGACYWINDOWSSTDIO
  $script:PreviousNoColor = $env:NO_COLOR
  $script:PreviousPyColors = $env:PY_COLORS
  $script:PreviousOutputEncoding = $OutputEncoding
  $script:PreviousConsoleOutputEncoding = [Console]::OutputEncoding

  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = $utf8
  $script:OutputEncoding = $utf8
  $env:PYTHONUTF8 = "1"
  $env:PYTHONIOENCODING = "utf-8"
  $env:PYTHONLEGACYWINDOWSSTDIO = "0"
  $env:NO_COLOR = "1"
  $env:PY_COLORS = "0"
}

function Restore-AiderUtf8Environment {
  if ($null -eq $script:PreviousPythonUtf8) { Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue } else { $env:PYTHONUTF8 = $script:PreviousPythonUtf8 }
  if ($null -eq $script:PreviousPythonIoEncoding) { Remove-Item Env:\PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $script:PreviousPythonIoEncoding }
  if ($null -eq $script:PreviousPythonLegacyWindowsStdio) { Remove-Item Env:\PYTHONLEGACYWINDOWSSTDIO -ErrorAction SilentlyContinue } else { $env:PYTHONLEGACYWINDOWSSTDIO = $script:PreviousPythonLegacyWindowsStdio }
  if ($null -eq $script:PreviousNoColor) { Remove-Item Env:\NO_COLOR -ErrorAction SilentlyContinue } else { $env:NO_COLOR = $script:PreviousNoColor }
  if ($null -eq $script:PreviousPyColors) { Remove-Item Env:\PY_COLORS -ErrorAction SilentlyContinue } else { $env:PY_COLORS = $script:PreviousPyColors }
  if ($script:PreviousConsoleOutputEncoding) { [Console]::OutputEncoding = $script:PreviousConsoleOutputEncoding }
  if ($script:PreviousOutputEncoding) { $script:OutputEncoding = $script:PreviousOutputEncoding }
}

function Read-SimpleYaml {
  param([string]$Path)
  $data = @{}
  $current = ""
  function Convert-YamlValue {
    param([string]$Value)
    $text = $Value.Trim()
    if ($text.Length -ge 2 -and $text.StartsWith('"') -and $text.EndsWith('"')) {
      $text = $text.Substring(1, $text.Length - 2)
    }
    return $text.Replace('\"', '"')
  }
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match "^([A-Za-z0-9_]+):\s*(.*?)\s*$") {
      $current = $Matches[1]
      $value = Convert-YamlValue -Value $Matches[2]
      if ($value.Length -gt 0) { $data[$current] = $value } else { $data[$current] = @() }
      continue
    }
    if ($current -and $line -match "^\s*-\s*(.*?)\s*$") {
      $value = Convert-YamlValue -Value $Matches[1]
      $data[$current] = @($data[$current]) + $value
    }
  }
  return $data
}

$workspace = (Resolve-Path -LiteralPath $WorkspacePath).ProviderPath
$ticket = (Resolve-Path -LiteralPath $TicketPath).ProviderPath
$contextPack = (Resolve-Path -LiteralPath $ContextPackPath).ProviderPath
$snapshot = Join-Path $workspace "source_snapshot"
if (-not (Test-Path -LiteralPath $snapshot)) { throw "Snapshot introuvable: $snapshot" }

$data = Read-SimpleYaml -Path $ticket
$ticketId = $data["id"]
if ([string]::IsNullOrWhiteSpace($ticketId)) { throw "Ticket sans id: $ticket" }
$safeId = ($ticketId -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
$editable = @($data["editable_files"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$readonly = @($data["readonly_files"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$runDir = Join-Path $workspace "fix_runs"
$validationDir = Join-Path $workspace "validation"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
New-Item -ItemType Directory -Path $validationDir -Force | Out-Null

$messagePath = Join-Path $runDir ($safeId + "_aider_message.md")
$messageLines = New-Object System.Collections.Generic.List[string]
$relativePack = [System.IO.Path]::GetFullPath($contextPack).Substring([System.IO.Path]::GetFullPath($snapshot).TrimEnd("\").Length).TrimStart("\") -replace "\\", "/"
if ($relativePack.StartsWith("..")) {
  $relativePack = $contextPack
}
$messageLines.Add("/read-only " + $relativePack) | Out-Null
foreach ($file in $readonly) { $messageLines.Add("/read-only " + (($file -replace "\\", "/").Trim("/"))) | Out-Null }
$messageLines.Add("") | Out-Null
$messageLines.Add("Tu corriges uniquement le ticket fourni dans le pack read-only.") | Out-Null
$messageLines.Add("Tu ne dois modifier que les fichiers editables passes a Aider.") | Out-Null
$messageLines.Add("N'invente pas de fichiers, fonctions, routes, commandes ou APIs absents du contexte.") | Out-Null
$messageLines.Add("Applique la correction minimale et respecte les criteres d'acceptation.") | Out-Null
Write-Utf8NoBom -Path $messagePath -Content ($messageLines -join [Environment]::NewLine)

$snapshotRootLength = $snapshot.TrimEnd("\").Length
$baseline = @()
Get-ChildItem -LiteralPath $snapshot -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($snapshotRootLength).TrimStart("\") -replace "\\", "/"
  $baseline += [pscustomobject][ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
}
Write-Utf8NoBom -Path (Join-Path $validationDir ($safeId + "_baseline.json")) -Content ($baseline | ConvertTo-Json -Depth 6)

$editableArgs = @()
foreach ($file in $editable) {
  $absolute = Join-Path $snapshot (($file -replace "\\", "/").Trim("/") -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Fichier editable introuvable: $file" }
  $editableArgs += $absolute
}
$args = @("--model", $Model, "--no-auto-commits", "--no-dirty-commits") + $editableArgs + @("--message-file", $messagePath)
$display = "aider " + (($args | ForEach-Object { Quote-Arg $_ }) -join " ")

Write-Host "=== Aider fix command ==="
Write-Host ("Workspace: " + $workspace)
Write-Host ("Snapshot:  " + $snapshot)
Write-Host ("Ticket:    " + $ticket)
Write-Host $display
Write-Host ""

if ($DryRun) {
  Write-Host "DryRun actif: Aider n'a pas ete lance."
} else {
  Enable-AiderUtf8Environment
  Push-Location $snapshot
  try {
    & aider @args
    if ($LASTEXITCODE -ne 0) { throw "Aider a retourne le code $LASTEXITCODE" }
  } finally {
    Pop-Location
    Restore-AiderUtf8Environment
  }
}

Write-Host ""
Write-Host "Next command:"
Write-Host ("powershell -ExecutionPolicy Bypass -File " + (Quote-Arg "C:\AI_ControlTower\tools\Test-AiderFix.ps1") + " -WorkspacePath " + (Quote-Arg $workspace) + " -TicketPath " + (Quote-Arg $ticket) + " -ContextPackPath " + (Quote-Arg $contextPack))
