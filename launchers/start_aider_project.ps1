param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$Model = "ollama_chat/ornith:9b"
)

Write-Host "=== AI Control Tower - Aider launcher ==="
Write-Host "Projet : $ProjectPath"
Write-Host "Modèle : $Model"

if (!(Test-Path $ProjectPath)) {
  Write-Error "Projet introuvable : $ProjectPath"
  exit 1
}

Set-Location $ProjectPath

git status

aider --model $Model --no-auto-commits --no-dirty-commits
