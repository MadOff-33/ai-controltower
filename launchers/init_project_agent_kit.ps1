param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$ProjectName = ""
)

Write-Host "=== AI Control Tower - Init Project Agent Kit ==="

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (!(Test-Path $ProjectPath)) {
  Write-Error "Projet introuvable : $ProjectPath"
  exit 1
}

if (!(Test-Path "$ProjectPath\.git")) {
  Write-Error "Le dossier n'est pas un depot Git : $ProjectPath"
  exit 1
}

if ($ProjectName -eq "") {
  $ProjectName = Split-Path $ProjectPath -Leaf
}

Write-Host "Projet : $ProjectName"
Write-Host "Chemin : $ProjectPath"

New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent\selected-skills" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent\selected-skills\policies" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent\selected-skills\bmad" | Out-Null
New-Item -ItemType Directory -Force -Path "$ProjectPath\.agent\selected-skills\superpowers" | Out-Null

if (!(Test-Path "$ProjectPath\AGENTS.md")) {
  Copy-Item "C:\AI_ControlTower\skills\project_templates\AGENTS.template.md" "$ProjectPath\AGENTS.md" -Force
}

if (!(Test-Path "$ProjectPath\.agent\PROJECT_CONTEXT.md")) {
  Copy-Item "C:\AI_ControlTower\skills\project_templates\PROJECT_CONTEXT.template.md" "$ProjectPath\.agent\PROJECT_CONTEXT.md" -Force
}

if (!(Test-Path "$ProjectPath\.agent\PROJECT_RULES.md")) {
  Copy-Item "C:\AI_ControlTower\skills\project_templates\PROJECT_RULES.template.md" "$ProjectPath\.agent\PROJECT_RULES.md" -Force
}

if (!(Test-Path "$ProjectPath\.agent\skills.lock.md")) {
  Copy-Item "C:\AI_ControlTower\skills\project_templates\skills.lock.template.md" "$ProjectPath\.agent\skills.lock.md" -Force
}

$aiderConfig = @'
model: ollama_chat/ornith:9b
auto-commits: false
dirty-commits: false
chat-language: fr
commit-language: fr
map-tokens: 4096
'@

[System.IO.File]::WriteAllText("$ProjectPath\.aider.conf.yml", $aiderConfig, $utf8NoBom)

$gitignore = "$ProjectPath\.gitignore"

if (!(Test-Path $gitignore)) {
  [System.IO.File]::WriteAllText($gitignore, "", $utf8NoBom)
}

$gitignoreContent = Get-Content $gitignore -Raw -ErrorAction SilentlyContinue

if ($gitignoreContent -notmatch [regex]::Escape("!.aider.conf.yml")) {
  [System.IO.File]::AppendAllText($gitignore, "`n# AI ControlTower project config`n!.aider.conf.yml`n", $utf8NoBom)
}

Copy-Item "C:\AI_ControlTower\policies\NO_PROD_WITHOUT_GO.md" "$ProjectPath\.agent\selected-skills\policies\NO_PROD_WITHOUT_GO.md" -Force
Copy-Item "C:\AI_ControlTower\policies\NO_SECRETS.md" "$ProjectPath\.agent\selected-skills\policies\NO_SECRETS.md" -Force
Copy-Item "C:\AI_ControlTower\policies\GIT_RULES.md" "$ProjectPath\.agent\selected-skills\policies\GIT_RULES.md" -Force

Copy-Item "C:\AI_ControlTower\skills\bmad\adapted-for-aider\bmad_core_aider.md" "$ProjectPath\.agent\selected-skills\bmad\bmad_core_aider.md" -Force
Copy-Item "C:\AI_ControlTower\skills\bmad\adapted-for-aider\bmad_dev_workflow_aider.md" "$ProjectPath\.agent\selected-skills\bmad\bmad_dev_workflow_aider.md" -Force

Copy-Item "C:\AI_ControlTower\skills\superpowers\adapted-for-aider\superpowers_core_aider.md" "$ProjectPath\.agent\selected-skills\superpowers\superpowers_core_aider.md" -Force

$loader = @'
/read-only .agent/selected-skills/policies/NO_PROD_WITHOUT_GO.md
/read-only .agent/selected-skills/policies/NO_SECRETS.md
/read-only .agent/selected-skills/policies/GIT_RULES.md
/read-only .agent/selected-skills/bmad/bmad_core_aider.md
/read-only .agent/selected-skills/bmad/bmad_dev_workflow_aider.md
/read-only .agent/selected-skills/superpowers/superpowers_core_aider.md
/read-only AGENTS.md
/read-only .agent/PROJECT_CONTEXT.md
/read-only .agent/PROJECT_RULES.md
/read-only .agent/skills.lock.md
'@

[System.IO.File]::WriteAllText("$ProjectPath\.agent\load_core_skills.aider", $loader, $utf8NoBom)

$readme = @"
# Projet : $ProjectName

Initialisation agentique effectuee depuis :

C:\AI_ControlTower

Date : initialisation agentique

Fichiers cles :
- AGENTS.md
- .aider.conf.yml
- .agent/PROJECT_CONTEXT.md
- .agent/PROJECT_RULES.md
- .agent/skills.lock.md
- .agent/selected-skills/
- .agent/load_core_skills.aider

Commande Aider apres lancement :

/load .agent/load_core_skills.aider
"@

[System.IO.File]::WriteAllText("$ProjectPath\.agent\README.md", $readme, $utf8NoBom)

Write-Host ""
Write-Host "Kit agent projet installe / mis a jour."
Write-Host ""
Write-Host "Prochaine verification :"
Write-Host "cd `"$ProjectPath`""
Write-Host "git status"