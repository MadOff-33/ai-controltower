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

function Get-NewestDirectory {
  param([string]$Path)
  $dir = Get-ChildItem -LiteralPath $Path -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $dir) { throw "Aucun workspace trouve dans: $Path" }
  return $dir.FullName
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
