# 01 — Installation du socle

## 1. Créer ou ouvrir le projet

Pour un nouveau projet :

~~~
mkdir -p /home/mike/workspace/<nom-projet>
cd /home/mike/workspace/<nom-projet>
git init -b main
~~~

Pour un projet existant :

~~~
cd /home/mike/workspace/<nom-projet>
git status
git remote -v
~~~

## 2. Installer BMAD en stable

Lancer l'installateur interactif :

~~~
npx bmad-method install
~~~

Choisir :

1. le répertoire du projet ;
2. le module BMM ;
3. le module TEA uniquement si le projet le justifie ;
4. l'outil utilisé par Codex et Claude ;
5. la langue française ;
6. _bmad-output comme dossier de sortie ;
7. le canal stable.

Après installation :

~~~
find _bmad -maxdepth 2 -type f | sort | head -80
find _bmad-output -maxdepth 3 -type f | sort
~~~

Les noms BMAD changent entre versions. Dans la version récente, utiliser notamment bmad-architecture, bmad-build, bmad-project-context et bmad-sprint-planning. Les anciens noms peuvent être des shims de compatibilité : ne pas mélanger les deux générations dans le workflow.

## 3. Installer Matt Pocock

~~~
npx skills@latest add mattpocock/skills
~~~

Sélectionner au minimum :

~~~
setup-matt-pocock-skills
grilling
domain-modeling
codebase-design
grill-with-docs
to-spec
to-tickets
implement
tdd
diagnosing-bugs
code-review
research
handoff
~~~

Ajouter wayfinder, prototype, triage et improve-codebase-architecture seulement si leur usage est prévu.

Puis lancer, une seule fois dans le projet :

~~~
/setup-matt-pocock-skills
~~~

Ce bootstrap configure le tracker, les labels et les documents de domaine utilisés par les skills Matt.

## 4. Installer Superpowers

### Codex App

Dans Codex : ouvrir Plugins, rechercher Superpowers, puis installer le plugin officiel.

### Claude Code

~~~
/plugin install superpowers@claude-plugins-official
~~~

### Aider ou GLM

Ne pas dépendre d'un plugin natif. Utiliser les fichiers Markdown du dossier 05-adapters et les contrats du dossier 04-contracts.

## 5. Vérifier l'absence de doublons

~~~
find .agents/skills -maxdepth 2 -type f 2>/dev/null | sort
find .claude/skills -maxdepth 2 -type f 2>/dev/null | sort
find _bmad -maxdepth 3 -type f 2>/dev/null | sort | head -100
~~~

Ne pas installer deux copies différentes d'un skill portant le même nom dans le même espace de découverte.

