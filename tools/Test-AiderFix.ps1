param(
  [Parameter(Mandatory = $true)]
  [string]$WorkspacePath,

  [Parameter(Mandatory = $true)]
  [string]$TicketPath,

  [Parameter(Mandatory = $true)]
  [string]$ContextPackPath
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-FileHashSafe {
  param([string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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
$validationDir = Join-Path $workspace "validation"
$data = Read-SimpleYaml -Path $ticket
$ticketId = $data["id"]
if ([string]::IsNullOrWhiteSpace($ticketId)) { throw "Ticket sans id: $ticket" }
$safeId = ($ticketId -replace '[^a-zA-Z0-9_.-]', '_').Trim("_")
$editable = @($data["editable_files"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ($_ -replace "\\", "/").Trim("/") })
$commands = @($data["verification_commands"] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$baselinePath = Join-Path $validationDir ($safeId + "_baseline.json")
if (-not (Test-Path -LiteralPath $baselinePath)) { throw "Baseline introuvable: $baselinePath" }

$baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$baselineMap = @{}
foreach ($item in $baseline) { $baselineMap[$item.path] = $item }

$snapshotRootLength = $snapshot.TrimEnd("\").Length
$currentMap = @{}
Get-ChildItem -LiteralPath $snapshot -Recurse -File -Force | ForEach-Object {
  $relative = $_.FullName.Substring($snapshotRootLength).TrimStart("\") -replace "\\", "/"
  $currentMap[$relative] = [pscustomobject][ordered]@{
    path = $relative
    size_bytes = $_.Length
    sha256 = Get-FileHashSafe -Path $_.FullName
  }
}

$changes = @()
foreach ($path in $currentMap.Keys) {
  if (-not $baselineMap.ContainsKey($path)) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "created" }
  } elseif ($baselineMap[$path].sha256 -ne $currentMap[$path].sha256) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "modified" }
  }
}
foreach ($path in $baselineMap.Keys) {
  if (-not $currentMap.ContainsKey($path)) {
    $changes += [pscustomobject][ordered]@{ path = $path; change = "deleted" }
  }
}

$unauthorized = @()
foreach ($change in $changes) {
  if ($editable -notcontains $change.path) {
    $unauthorized += $change
  }
}

$contextText = Get-Content -LiteralPath $contextPack -Raw
$ghostMarkers = @("main()", "app.run()", "sys.exit(app.exec_())")
$ghostFindings = @()
foreach ($change in $changes) {
  if ($editable -notcontains $change.path) { continue }
  if ($change.change -eq "deleted") { continue }
  $absolute = Join-Path $snapshot ($change.path -replace "/", "\")
  if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
  $text = Get-Content -LiteralPath $absolute -Raw
  foreach ($marker in $ghostMarkers) {
    if ($text.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $contextText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
      $ghostFindings += [pscustomobject][ordered]@{ path = $change.path; marker = $marker }
    }
  }
}

$commandResults = @()
if (($unauthorized.Count -eq 0) -and ($ghostFindings.Count -eq 0)) {
  foreach ($command in $commands) {
    Push-Location $snapshot
    try {
      $output = cmd.exe /c $command 2>&1
      $code = $LASTEXITCODE
    } finally {
      Pop-Location
    }
    $commandResults += [pscustomobject][ordered]@{ command = $command; exit_code = $code; output = ($output -join [Environment]::NewLine) }
  }
}

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
Write-Utf8NoBom -Path (Join-Path $validationDir ($safeId + "_result.json")) -Content ($result | ConvertTo-Json -Depth 8)

Write-Host "=== Aider fix validation ==="
Write-Host ("Changes:              " + $changes.Count)
Write-Host ("Unauthorized changes: " + $unauthorized.Count)
Write-Host ("Ghost findings:       " + $ghostFindings.Count)
Write-Host ("Failed commands:      " + $failedCommands.Count)
if ($unauthorized.Count -gt 0) {
  Write-Host ""
  Write-Host "Unauthorized files:"
  $unauthorized | ForEach-Object { Write-Host ("- " + $_.change + ": " + $_.path) }
}
if ($ghostFindings.Count -gt 0) {
  Write-Host ""
  Write-Host "Ghost findings:"
  $ghostFindings | ForEach-Object { Write-Host ("- " + $_.path + ": " + $_.marker) }
}

if ($passed) {
  Write-Host "Validation passed."
  exit 0
}

Write-Host "Validation failed."
exit 1
