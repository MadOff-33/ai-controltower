# 00 — Pré-requis

## Environnement recommandé

- WSL2 Ubuntu comme environnement canonique ;
- projets sous /home/mike/workspace ;
- dépôt Windows conservé séparément comme rollback si nécessaire ;
- Git installé et configuré ;
- Claude Code exécuté dans WSL ;
- Codex utilisé comme orchestrateur ;
- GLM accessible via l'outil retenu ;
- aucun secret copié dans le dossier de workflow.

## Vérification des versions

Depuis WSL :

~~~
uname -a
cat /etc/os-release
node --version
npm --version
git --version
python3 --version
uv --version
~~~

BMAD indique Node.js 20.12+ pour son installateur. Les versions récentes de ses workflows rendus utilisent également uv et Python 3.11+ pour les scripts concernés. Vérifier les exigences de la version stable installée avant exécution.

## Installation des prérequis manquants

Ne pas installer une version next pour un projet de production.

Pour uv, utiliser la documentation officielle :

https://docs.astral.sh/uv/getting-started/installation/

Puis rouvrir le shell et revérifier :

~~~
uv --version
~~~

## Vérification Git

~~~
git config --global user.name
git config --global user.email
git status
~~~

Si l'identité Git est absente, la configurer avant l'installation des workflows.

