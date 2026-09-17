# Préflight de session

À exécuter avant de choisir une route.

## 0. Résolution obligatoire du worktree actif — avant CONTEXT.md

Ne pas lire `CONTEXT.md`, `.workflow/state.yaml` du checkout courant, les ADR ou le sprint tant que cette étape n'est pas terminée.

1. Identifier le dépôt Git courant et lister tous ses worktrees avec `git worktree list --porcelain`.
2. Pour chaque worktree, relever uniquement avant le contexte métier :
   - le chemin ;
   - la branche ;
   - `git status --porcelain` ;
   - si présent, les champs de `.workflow/state.yaml` : `project_status`, `current_route`, `current_request`, `current_branch`, `current_gate`, `last_verified_commit`.
3. Considérer comme **signaux forts d'activité** :
   - `project_status: in_progress` ;
   - `current_request` non nul/non vide ;
   - un `current_gate` renseigné autre que `preflight`.
4. Considérer comme **signaux secondaires** :
   - des modifications/non-suivis dans le worktree ;
   - une branche différente de `main`/`master`.
5. Ignorer comme candidat actif un worktree explicitement `completed`, `done` ou `archived`, sauf demande explicite de l'utilisateur.
6. Si un seul worktree présente clairement les signaux forts, le sélectionner même si le checkout de départ est `main`/`master`.
7. Si aucun autre worktree ne présente de signal fort, conserver le checkout courant et signaler qu'aucun travail actif distinct n'a été détecté.
8. Si plusieurs worktrees présentent des signaux forts incompatibles, **ne pas choisir au hasard** : retourner `BLOCKED_WORKTREE` avec pour chaque candidat chemin, branche, statut, requête, gate et état dirty, puis demander lequel reprendre.
9. Si le worktree sélectionné diffère du checkout de départ, s'y placer et reprendre `.workflow/workflow-system/WORKFLOW.md` depuis l'étape 1. Ne pas réutiliser le `CONTEXT.md` ou l'état métier du checkout de départ.

Exemple de commandes de diagnostic :

~~~bash
git worktree list --porcelain
git -C "<worktree>" status --porcelain
~~~

Sous PowerShell, les mêmes commandes Git s'appliquent ; toujours citer les chemins contenant des espaces.

## 1. Préflight du worktree retenu

1. Lire WORKFLOW.md, MANIFEST.yaml, ROUTER.md, AGENTS.md/CLAUDE.md, CONTEXT.md, `.workflow/state.yaml` et les sources de vérité pertinentes **dans le worktree retenu**.
2. Inspecter l'état Git, la branche, la baseline et les travaux en cours.
3. Si la demande est une reprise de projet, reconstituer le contexte et la progression réels à partir des éléments déjà disponibles : travail réalisé, éléments ouverts ou incertains, décisions et validations explicites. Ne pas inventer une roadmap et ne pas assimiler un livrable terminé à un projet terminé.
4. Vérifier les runtimes du terminal courant avant d'utiliser les outils du workflow.
5. Identifier les commandes de test/build sans lire les secrets.
6. Classer ou confirmer la demande R0 à R5 à partir de l'état repris.
7. Charger réellement les `SKILL.md` requis par la route et les éventuels skills conditionnels retenus.
8. En reprise, utiliser la route, les skills et les agents chargés pour déterminer la suite logique à proposer à partir du contexte reconstitué ; ne pas figer cette suite dans le préflight.
9. La reprise seule n'autorise aucune nouvelle action technique : présenter d'abord la suite proposée par le workflow et attendre le gate applicable avant tests, build, installation, diagnostic, correction ou autre exécution nouvelle.
10. Annoncer les skills chargés, l'état repris, la suite proposée par le workflow, les sorties attendues et le gate suivant.
11. S'arrêter avant toute mutation si le GO requis n'est pas explicite.

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
Worktree sélectionné:
Raison de sélection:
Type de demande:
Niveau de risque:
Route:
Contexte repris:
État actuel reconstitué:
Baseline:
Branche/worktree:
Runtime:
Skills chargés et dépendances:
Suite proposée par le workflow:
Sorties:
Gate suivant:
~~~
