# Préflight de session

À exécuter avant de choisir une route.

1. Lire WORKFLOW.md, MANIFEST.yaml, ROUTER.md, AGENTS.md/CLAUDE.md, CONTEXT.md et les ADR pertinentes.
2. Inspecter l'état Git, la branche, la baseline et les travaux en cours.
3. Vérifier les runtimes du terminal courant avant d'utiliser les outils du workflow.
4. Identifier les commandes de test/build sans lire les secrets.
5. Classer la demande R0 à R5.
6. Charger réellement les `SKILL.md` requis par la route et les éventuels skills conditionnels retenus.
7. Annoncer les skills chargés, dépendances, sorties attendues et gate suivant.
8. S'arrêter avant toute mutation si le GO requis n'est pas explicite.

## Contrôle runtime obligatoire

Pour BMAD, la version minimale est celle de `VERSION.lock` : Node.js `>=20.12.0`.

Dans un terminal POSIX/WSL, si `node` n'est pas trouvé mais que `$HOME/.nvm/nvm.sh` existe, charger NVM dans le shell courant avant de conclure à une absence de Node :

~~~bash
if ! command -v node >/dev/null 2>&1 && [ -s "$HOME/.nvm/nvm.sh" ]; then
  export NVM_DIR="$HOME/.nvm"
  . "$NVM_DIR/nvm.sh"
fi
node --version
npm --version
npx --version
~~~

Sous PowerShell, vérifier au minimum `Get-Command node`, `node --version`, `npm --version` et `npx --version`.

Si Node reste absent ou est inférieur à 20.12.0, arrêter la route avec `BLOCKED_ENV`, indiquer le shell et le `PATH` observés, et ne pas affirmer que Node est absent de la machine entière.

Sortie minimale :

~~~text
Type de demande:
Niveau de risque:
Route:
Contexte lu:
Baseline:
Branche/worktree:
Runtime:
Skills chargés et dépendances:
Sorties:
Gate suivant:
~~~
