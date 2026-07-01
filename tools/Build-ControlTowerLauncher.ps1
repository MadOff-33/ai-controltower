param(
  [string]$Root = "C:\AI_ControlTower",
  [string]$OutputPath = "C:\AI_ControlTower\ControlTower.exe"
)

$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $Root "launchers\ControlTowerLauncher.cs"
if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Source launcher introuvable: $sourcePath" }

$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $compiler)) {
  $compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $compiler)) { throw "Compilateur C# .NET Framework introuvable." }

$args = @(
  "/nologo",
  "/target:winexe",
  "/platform:anycpu",
  "/out:$OutputPath",
  $sourcePath
)

& $compiler @args
if ($LASTEXITCODE -ne 0) { throw "Compilation ControlTower.exe echouee." }
if (-not (Test-Path -LiteralPath $OutputPath)) { throw "ControlTower.exe non genere: $OutputPath" }

Write-Host "=== ControlTower launcher built ==="
Write-Host ("Exe: " + $OutputPath)
Write-Host ""
Write-Host "Next command:"
Write-Host $OutputPath
