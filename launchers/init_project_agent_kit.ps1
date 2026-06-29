param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$ProjectName = ""
)

Write-Host "=== AI Control Tower - Init Project Agent Kit ==="

if (!(Test-Path $ProjectPath)) {
  Write-Error "Projet introuvable : $ProjectPath"
  exit 1
}

if (!(Test-Path "$ProjectPath\.git")) {
  Write-Error "Le dossier n'est pas un dépôt Git : $ProjectPath"
  exit 1
}

if ($ProjectName -eq "") {
  $ProjectName = Split-Path $ProjectPath -Leaf
}

Write-Host "Projet : $ProjectName"
Write-Host "Chemin : $ProjectPath"

New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent\selected-skills" | Out-Null

Copy-Item "C:\AI_ControlTower\skills\project_templates\AGENTS.template.md" "$ProjectPath\AGENTS.md" -Force
Copy-Item "C:\AI_ControlTower\skills\project_templates\aider.conf.template.yml" "$ProjectPath\.aider.conf.yml" -Force
Copy-Item "C:\AI_ControlTower\skills\project_templates\PROJECT_CONTEXT.template.md" "$ProjectPath\.agent\PROJECT_CONTEXT.md" -Force
Copy-Item "C:\AI_ControlTower\skills\project_templates\PROJECT_RULES.template.md" "$ProjectPath\.agent\PROJECT_RULES.md" -Force
Copy-Item "C:\AI_ControlTower\skills\project_templates\skills.lock.template.md" "$ProjectPath\.agent\skills.lock.md" -Force

@"
# Projet : $ProjectName

Initialisation agentique effectuée depuis :

C:\AI_ControlTower

Date : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

À compléter avant usage réel :
- .agent/PROJECT_CONTEXT.md
- .agent/PROJECT_RULES.md
- .agent/skills.lock.md
"@ | Set-Content "$ProjectPath\.agent\README.md" -Encoding UTF8

Write-Host ""
Write-Host "Kit agent projet installé."
Write-Host ""
Write-Host "Prochaine vérification :"
Write-Host "cd `"$ProjectPath`""
Write-Host "git status"
