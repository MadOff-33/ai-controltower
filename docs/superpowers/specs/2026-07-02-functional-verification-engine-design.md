# Moteur de vérification fonctionnelle — Sous-projet 1

**Date:** 2026-07-02
**Status:** Approved
**Origine:** Neon Paddle (jeu Pong) a été marqué `passed` deux fois par le pipeline alors que le jeu était fonctionnellement cassé (HTML vide, IA plantant sur une référence `null`, écrans jamais atteignables). Le validateur existant (`Test-AiderCreation.ps1` / `Test-AiderOutput.ps1` / `Test-AiderFix.ps1`) ne vérifie que la structure (encodage, fichiers interdits, marqueurs fantômes) — jamais l'exécution réelle.

## Contexte programme

Suite du programme à 4 sous-projets défini le 2026-07-02 (voir `docs/superpowers/specs/2026-07-02-pipeline-reliability-observability-design.md` pour le Sous-projet 4, déjà livré). Ce document couvre le **Sous-projet 1**, bloquant pour le Sous-projet 2 (boucle de renforcement Hermes) puisque le renforcement a besoin d'un vrai signal succès/échec pour apprendre correctement.

### Principes transverses (rappel, s'appliquent ici aussi)

- Configurabilité explicite dans l'UI.
- Généralisation : aucune règle ne doit être pensée pour un projet particulier.
- Renforcement anti-faux-positif : aucune promotion en mémoire Hermes sans vérification réelle.
- UX explicite : l'utilisateur doit toujours savoir ce qui se passe et pouvoir agir.

## Objectif

Ajouter une vérification d'exécution réelle (pas seulement structurelle) après une **création** ou une **correction** de projet, faire de son résultat une condition bloquante du statut `passed`/`failed` global, afficher le résultat en langage simple directement dans l'interface (audit ET création), et donner à l'utilisateur un moyen d'agir immédiatement (« Corriger ce projet ») quand ça échoue.

## Non-goals

- Pas de test interactif profond (parcourir tous les écrans, cliquer tous les boutons) — seulement le chargement initial de la page et capture des erreurs console.
- Pas d'analyse JS par AST complet — recoupement DOM par heuristique regex, dans le même esprit que les détecteurs de mojibake déjà présents dans ce dépôt.
- Pas de boucle de correction automatique multi-tentatives — le bouton « Corriger ce projet » déclenche **une** passe manuelle, décidée par l'utilisateur (l'automatisation de cette boucle est le Sous-projet 2).
- **Le mode Audit n'est pas concerné** : un audit produit un rapport d'analyse, pas un changement exécutable — il n'y a rien à « faire tourner ». La vérification fonctionnelle s'applique uniquement à **Creation** et **Fix**, qui modifient ou créent du code censé s'exécuter.
- Pas d'inférence de type de projet au-delà d'heuristiques simples par extension de fichier.

## Contexte gathered

- `PROJECT_TYPES` (dans `apps/controltower-ui/app.py`) : `python-cli, python-app, webapp, api, desktop, library, other`.
- `creation.config.json` (écrit par `New-CreationWorkspace.ps1`) porte déjà le type de projet choisi à la création.
- Le mode Fix opère sur un snapshot d'un projet réel existant, audité au préalable — il n'y a pas de « type déclaré » disponible à ce stade ; une détection par extension de fichiers est nécessaire.
- Node.js est déjà présent sur ce poste (confirmé : `D:\node.exe`) mais aucun outil de navigateur headless n'est installé.
- `.status-band` (audit) affiche déjà un statut global (`#lastRunStatus`) alimenté par `state.last_run`, lui-même dérivé de `read_last_run_status()` dans `app.py`, qui lit le run log JSON écrit par `New-RunLog` dans `Invoke-ControlTowerRun.ps1`. C'est le point d'intégration naturel pour remonter le résumé fonctionnel jusqu'à l'UI sans construire un nouveau canal.
- L'onglet Création n'a aujourd'hui aucun panneau de statut équivalent (seulement `#creationJobPanel` / `#creationLogPanel`), et aucun bouton de reprise/correction — contrairement à l'audit qui a « Continuer l'audit ». `Invoke-ControlTowerRun.ps1 -Mode Creation` accepte déjà `-AllowExisting` côté PowerShell (ajouté avant ce sous-projet) mais ce n'est jamais exposé par `POST /api/new-project`.
- Le panneau Dépendances existant (`#dependencyList`, alimenté par `Test-ControlTowerDependencies.ps1`) est le point d'intégration naturel pour afficher la disponibilité du navigateur headless.

## Design

### 1. `tools/Test-ProjectFunctional.ps1` — moteur de vérification

Signature : `-ProjectPath <string> [-ProjectType <string>]`. Si `-ProjectType` est omis (cas du mode Fix), le script détecte lui-même : présence d'un `.html` à la racine → traité comme `webapp` ; sinon présence de fichiers `.py` → traité comme Python ; sinon → `not_verified`.

Sortie JSON sur stdout :
```json
{
  "status": "ok" | "failed" | "not_verified",
  "summary": "<phrase en français simple, sans jargon>",
  "checks": [
    { "name": "dom_reference_check", "status": "ok", "detail": "..." },
    { "name": "browser_console", "status": "failed", "detail": "..." }
  ]
}
```
Code de sortie 0 si `status` = `ok` ou `not_verified` (rien à bloquer), 1 si `failed`.

### 2. Contrôles par type

- **webapp** : délègue à `tools/headless/check-webapp.js` (voir §3) qui fait (a) le recoupement statique `getElementById`/`querySelector` du JS contre les `id`/`class` du HTML — exactement la méthode qui a détecté le bug critique de Neon Paddle — puis (b) le chargement réel de la page dans Chromium headless avec capture des erreurs console (`console.error` + `pageerror`) pendant une fenêtre de quelques secondes.
- **python-cli / python-app / api / library** (une seule fonction PowerShell partagée) : `python -m py_compile` sur chaque `.py` (erreur de syntaxe → `failed` immédiat) ; si un dossier/fichier de test est présent (`tests/`, `test_*.py`, `*_test.py`) → exécution via `pytest`, résultat = statut final ; sinon → `status: "ok"` avec un résumé honnête (« le code compile sans erreur, mais aucun test n'a été trouvé pour vérifier le comportement »).
- **desktop / other** : même logique de détection par extension que le mode Fix sans type déclaré (réutilise le même chemin de code) — best-effort ou `not_verified` si rien de reconnaissable.

### 3. Nouvelle dépendance : Playwright (Chromium seul)

`tools/headless/` : dossier avec son propre `package.json` (dépendance `playwright`) et `check-webapp.js`. Installation via `npm install` + `npx playwright install chromium` (ajouté à `Install-ControlTower.ps1`). `Test-ControlTowerDependencies.ps1` gagne un contrôle de présence (`node`, module `playwright` installé), visible automatiquement dans le panneau Dépendances existant.

### 4. Intégration dans les validateurs existants

- `Test-AiderCreation.ps1` : après ses contrôles structurels actuels, appelle `Test-ProjectFunctional.ps1 -ProjectPath <target> -ProjectType <depuis creation.config.json>`. Un `status: "failed"` fait passer la validation globale à `failed` (jamais `passed`).
- `Test-AiderFix.ps1` : même intégration, sans `-ProjectType` (détection automatique sur le snapshot corrigé).
- `Test-AiderOutput.ps1` (audit) : **non modifié**, conformément au non-goal.
- Le résultat complet (`status`, `summary`, `checks`) est écrit dans `validation/pipeline_result.json` (creation) et le fichier `*_pipeline_result.json` équivalent (fix), sous une clé `functional_check`.

### 5. Remontée du résumé jusqu'à l'UI

`Invoke-ControlTowerRun.ps1` lit `functional_check` depuis le `pipeline_result.json` du mode concerné et l'ajoute au `$result` passé à `New-RunLog`, donc au run log JSON. `read_last_run_status()` (`app.py`) expose ce champ dans la réponse de `/api/state`. Côté UI :
- **Audit/Correction** : nouvelle ligne sous `#lastRunStatus` dans `.status-band` — badge coloré (vert `ok`, rouge `failed`, gris `not_verified`) + la phrase de `summary`.
- **Création** : nouveau panneau de statut équivalent ajouté près de `#creationJobPanel` (aujourd'hui inexistant pour cet onglet), même badge + même phrase.

### 6. Bouton « Corriger ce projet » (Création)

- **Détection** : nouvel endpoint `GET /api/new-project/status?project_name=...&parent_path=...` — cherche le workspace de création le plus récent dont `target_project_path` correspond, lit son `functional_check`. Réponse : `{ has_previous: bool, functional_status: "ok"|"failed"|"not_verified"|null, checks: [...] }`. Le frontend l'appelle quand nom + dossier parent sont renseignés.
- **UI** : si `functional_status == "failed"`, un champ « Notes de correction » apparaît, **pré-rempli automatiquement** à partir de `checks` (éditable), avec un bouton « Corriger et relancer Aider » à côté du bouton « Lancer Aider » existant.
- **Backend** : `POST /api/new-project` gagne deux champs optionnels : `allow_existing: bool`, `correction_notes: string`. Quand `allow_existing` est vrai : la vérification « dossier vide obligatoire » est sautée, le brief original du workspace précédent est relu, une section `## Correction requise` contenant `correction_notes` lui est ajoutée, le tout est persisté dans un nouveau fichier brief, et le pipeline est invoqué avec `-Mode Creation -AllowExisting -BriefPath <nouveau fichier>` — reproduction exacte du cycle manuel effectué aujourd'hui sur Neon Paddle, rendu accessible sans terminal.

## Testing / verification plan

- `tools/tests/Test-ProjectFunctionalCheck.ps1` (nouveau) : fixtures couvrant chaque branche — webapp avec HTML valide (ok), webapp avec référence DOM manquante (failed), webapp avec erreur console au chargement (failed), projet Python avec tests qui passent (ok), avec tests qui échouent (failed), sans tests (ok avec résumé honnête), type non reconnu (not_verified).
- `apps/controltower-ui/tests/test_app.py` : nouveaux tests pour `GET /api/new-project/status` et `POST /api/new-project` avec `allow_existing`/`correction_notes`.
- Vérification manuelle : relancer une création volontairement cassée (même patron que Neon Paddle) de bout en bout via l'UI et confirmer que (a) le statut global passe à `failed`, (b) le résumé en clair est visible sans ouvrir de rapport, (c) le bouton « Corriger » apparaît avec les notes pré-remplies, (d) une seconde passe corrige effectivement et fait passer le statut à `ok`.
- `powershell -File tools/tests/Invoke-ControlTowerTestSuite.ps1` et `powershell -File tools/tests/run_pytest.ps1 -Path apps/controltower-ui` restent verts.

## Risks / open questions

- Le poids de l'installation Playwright/Chromium (~150-200 Mo) est accepté comme coût du passage à une vérification réellement fonctionnelle.
- La fenêtre de capture des erreurs console (quelques secondes après chargement) est un compromis pragmatique — elle attrape les erreurs immédiates (comme le crash `canvas.getContext` de Neon Paddle) mais pas celles qui n'apparaissent qu'après une interaction utilisateur (hors périmètre, cf. Non-goals).
- Le recoupement DOM par regex peut avoir de faux négatifs sur du JS très dynamique (ids construits par concaténation) — accepté comme limite connue d'une heuristique, pas une garantie formelle.
