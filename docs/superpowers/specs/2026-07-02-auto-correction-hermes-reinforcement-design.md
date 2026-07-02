# Boucle d'auto-correction & renforcement Hermes — Sous-projet 2 (+ reliquat 3)

**Date:** 2026-07-02
**Status:** Approved
**Origine:** Le Sous-projet 1 (vérification fonctionnelle, livré) a donné un vrai signal succès/échec, mais chaque correction ratée retombe encore sur l'utilisateur (bouton "Corriger ce projet", une passe manuelle à la fois). Aujourd'hui, corriger Neon Paddle a demandé 6 passes manuelles ciblées (un fichier, un défaut) — ce sous-projet automatise exactement ce cycle, et fait apprendre Hermes de façon mesurable plutôt que par leçons en texte libre.

## Contexte programme

Ce document couvre le **Sous-projet 2** (boucle d'auto-correction + renforcement Hermes quantitatif) et absorbe le reliquat du **Sous-projet 3** (capture d'écran du smoke-test), puisque son périmètre d'origine (bouton "Corriger", badges de statut) a déjà été livré avec le Sous-projet 1. Le fix `Invoke-AiderAuditContinuation.ps1` (threading `-HermesMemoryRoot`) est **hors périmètre ici** — l'utilisateur l'a déjà lancé dans une session séparée.

**Dépendance :** ce sous-projet construit directement sur le code du Sous-projet 1 (`tools/Test-ProjectFunctional.ps1`, `tools/headless/check-webapp.js`, la propagation `functional_check`). Le Sous-projet 1 n'est pas encore mergé sur `main` (conservé tel quel sur sa branche) — ce travail démarre donc depuis la branche du Sous-projet 1, pas depuis `main`.

### Principes transverses (rappel)

- Généralisation : aucune règle ne doit être pensée pour un projet particulier.
- Renforcement anti-faux-positif : aucune promotion en mémoire Hermes sans vérification réelle.
- UX explicite : l'utilisateur doit toujours savoir ce qui se passe et pouvoir agir.

## Objectif

Après un échec de vérification fonctionnelle en Création ou Correction, relancer automatiquement Aider en ciblant un seul fichier à la fois sur le défaut détecté, jusqu'à 5 tentatives ou succès, en enregistrant dans Hermes un taux de réussite mesurable par type de défaut — pas juste une leçon qualitative.

## Non-goals

- Pas d'intervention interactive en cours de boucle (elle tourne jusqu'au bout ou jusqu'à épuisement, comme n'importe quel job existant — pas de pause/ajustement à mi-parcours).
- Pas de boucle pour le mode Audit (toujours hors périmètre, un audit ne produit rien d'exécutable).
- Pas de nouvelle dépendance (réutilise Playwright déjà installé par le Sous-projet 1 pour la capture d'écran).
- Pas de transfert d'apprentissage entre projets au-delà de ce que Hermes fait déjà (comptage structuré dans la mémoire JSON-lines existante, pas un modèle séparé).
- Le fix `Invoke-AiderAuditContinuation.ps1` reste hors périmètre (déjà en cours ailleurs).

## Contexte gathered

- `Test-ProjectFunctional.ps1` court-circuite déjà ses propres contrôles (`dom_reference_check` avant `browser_console` ; `python_syntax` avant `python_tests`) — en pratique, un seul `checks[]` peut être en échec à la fois par run. La boucle n'a donc pas besoin d'itérer une liste de défauts simultanés : elle relance le contrôle complet après chaque correction et découvre le prochain défaut, exactement comme le déroulé manuel d'aujourd'hui.
- `check-webapp.js` calcule déjà `htmlPath` et `scriptFiles` en interne mais ne les expose pas dans son JSON de sortie — nécessaire pour que la boucle PowerShell cible le bon fichier sans reparser le HTML elle-même.
- Pour `python_syntax`, `checks[].detail` contient déjà les chemins de fichiers en échec (`$syntaxErrors -join ", "`) — le premier chemin donne la cible.
- Pour `python_tests`, la sortie pytest ne pointe pas de façon fiable vers un seul fichier — pas de ciblage fichier unique dans ce cas (voir Design §2).
- `Get-HermesGuidance.ps1` rend déjà les entrées comme `- [kind/category] summary` — un format texte simple à étendre pour inclure des statistiques agrégées sans changer le format de stockage (`entries.jsonl`, une entrée JSON par ligne).

## Design

### 1. `tools/Invoke-AutoCorrectionLoop.ps1` — moteur de la boucle

Signature : `-ProjectPath <string> [-ProjectType <string>] -WorkspacePath <string> -HermesMemoryRoot <string> [-MaxAttempts <int> = 5]`.

Boucle :
```
attempt = 0
while attempt < MaxAttempts:
  result = Test-ProjectFunctional.ps1 -ProjectPath -ProjectType
  if result.status != "failed": break
  failedCheck = premier element de result.checks avec status="failed"
  targetFile = Get-TargetFileForCheck(failedCheck, result)
  brief = Build-CorrectionBrief(failedCheck)
  Invoke Aider cible sur targetFile (ou tous les fichiers source pertinents si python_tests)
  attempt++
  Add-HermesMemoryEntry: tentative n° attempt, check=failedCheck.name, resultat connu au tour suivant
finalResult = Test-ProjectFunctional.ps1 (dernier etat)
```

Sortie : `{ resolved: bool, attempts_used: int, max_attempts: int, final_check: <functional_check>, history: [{attempt, check_name, target_file, outcome: "fixed"|"not_fixed"}] }`, écrite dans `validation/auto_correction_result.json` du workspace.

Appelée depuis `Invoke-AiderCreationPipeline.ps1` et `Invoke-AiderFixPipeline.ps1`, juste après leur validation initiale, uniquement si `functional_check.status == "failed"` (structure déjà correcte — pas la peine de boucler si les vérifications structurelles échouent, ce n'est pas ce que cette boucle corrige).

### 2. Ciblage du fichier par type de défaut

- `dom_reference_check` échoue → cible le fichier HTML (`html_file`, nouveau champ exposé par `check-webapp.js`, voir §4). La correction consiste à ajouter l'élément manquant, pas à retirer la référence JS — reproduit la stratégie qui a marché sur Neon Paddle.
- `browser_console` échoue → cible le premier fichier de `script_files` (nouveau champ exposé par `check-webapp.js`).
- `python_syntax` échoue → cible le premier chemin listé dans `checks[].detail`.
- `python_tests` échoue → **pas de ciblage à un seul fichier** : Aider reçoit accès à tous les fichiers source Python (hors tests), car la sortie pytest ne pointe pas de façon fiable vers un seul fichier fautif. Exception assumée à la règle "un fichier à la fois", plutôt que d'inventer une heuristique de parsing fragile.

### 3. `Build-CorrectionBrief` — instructions génériques par type de défaut

Un message par type, jamais spécifique à un projet, construit à partir de `checks[].detail` :
- `dom_reference_check` : *"Le fichier JS référence un élément HTML manquant : {detail}. Ajoute l'élément manquant dans le fichier HTML avec l'id/class exact mentionné, sans rien supprimer d'existant."*
- `browser_console` : *"Le site plante au chargement avec cette erreur JavaScript : {detail}. Corrige le bug dans le code JavaScript qui cause cette erreur, sans changer le comportement du reste du code."*
- `python_syntax` : *"Le fichier contient une erreur de syntaxe : {detail}. Corrige uniquement l'erreur de syntaxe."*
- `python_tests` : *"Les tests échouent avec cette sortie : {detail}. Corrige le code pour que les tests passent, sans modifier les tests eux-mêmes."*

### 4. Renforcement Hermes quantitatif

`check-webapp.js` gagne deux champs top-level toujours présents (pas seulement en cas d'échec) : `html_file` et `script_files`. `Test-ProjectFunctional.ps1` les relaie tels quels dans son propre JSON.

Chaque tentative de la boucle enregistre une entrée Hermes via `Add-HermesMemoryEntry.ps1` avec `Kind="correction_attempt"`, `Category=<nom du check>`, et un `-ContextJson` structuré `{ outcome: "fixed"|"not_fixed", target_file, attempt_number }`. `Get-HermesGuidance.ps1` est étendu pour, en plus de sa liste d'entrées récentes existante, calculer et afficher un résumé agrégé par catégorie sur les 50 dernières tentatives : *"Taux de réussite auto-correction — dom_reference_check: 8/9 (89%), browser_console: 3/7 (43%)"*. Ce résumé apparaît dans le guidage envoyé à Aider (déjà le mécanisme existant), donnant un signal calibré et mesurable plutôt qu'une leçon en texte libre isolée.

Le résultat global de la boucle (`resolved`/`attempts_used`) devient aussi le signal final `run_outcome` enregistré dans Hermes pour cette création/correction — remplace le "passed" naïf d'avant le Sous-projet 1, qui ne mesurait que la structure.

### 5. Capture d'écran (reliquat Sous-projet 3)

`check-webapp.js` prend une capture d'écran Playwright (`page.screenshot()`) juste avant de fermer le navigateur, uniquement quand `browser_console` a échoué (pas la peine de capturer une page qui charge bien). Le fichier est écrit dans le workspace (`validation/screenshot.png`), et son chemin ajouté au JSON de sortie sous `screenshot_path`. Ce champ suit la chaîne de propagation déjà construite au Sous-projet 1 (`functional_check` → run log → `/api/state`) jusqu'à l'UI, où un nouvel `<img>` s'affiche à côté du résumé quand le champ est présent.

### 6. Visibilité UI de la boucle

Chaque tentative écrit une ligne `Write-Host` explicite ("=== Tentative de correction 2/5 : dom_reference_check dans index.html ===") — déjà visible en temps réel dans le panneau de job existant (mécanisme du Sous-projet 1, aucun nouveau code UI necessaire pour ça). Le résumé final (`functional_check.summary`, déjà affiché par le Sous-projet 1) est complété pour mentionner le nombre de tentatives : *"Corrigé automatiquement après 3 tentatives"* ou *"Échec après 5 tentatives, correction manuelle nécessaire"* — l'utilisateur garde le bouton "Corriger ce projet" existant pour reprendre la main après un échec de la boucle automatique.

## Testing / verification plan

- `tools/tests/Test-AutoCorrectionLoop.ps1` (nouveau) : fixtures avec des fausses invocations Aider (script simulant une correction qui réussit au 2e essai, une qui échoue aux 5, une qui réussit du premier coup) — vérifie le comptage de tentatives, l'arrêt à `MaxAttempts`, et le contenu de `auto_correction_result.json`.
- Test dédié pour `Get-TargetFileForCheck` : les 4 branches (dom_reference_check, browser_console, python_syntax, python_tests) avec des fixtures `functional_check` JSON directement construites (pas besoin de relancer le moteur complet).
- Test pour l'agrégation Hermes : seed plusieurs entrées `correction_attempt` connues, vérifie que `Get-HermesGuidance.ps1` calcule le bon taux de réussite par catégorie.
- `apps/controltower-ui/tests/test_app.py` : test que `screenshot_path`, quand présent dans `functional_check`, est bien exposé par `/api/state`.
- Vérification manuelle : reproduire un scénario proche de Neon Paddle (webapp avec un `id` manquant volontairement) via la Création réelle, confirmer que la boucle corrige automatiquement sans intervention, que Hermes enregistre le taux de réussite, et que la capture d'écran (si un `browser_console` a été rencontré en cours de route) s'affiche dans l'UI.
- `powershell -File tools/tests/Invoke-ControlTowerTestSuite.ps1` et `powershell -File tools/tests/run_pytest.ps1 -Path apps/controltower-ui` restent verts.

## Risks / open questions

- La qualité des corrections automatiques dépendra de la richesse de `checks[].detail` — moins précise que les corrections manuelles d'aujourd'hui, où un diagnostic humain (moi) lisait le code et donnait des instructions avant/après exactes. C'est un compromis assumé : l'automatisation vise à reproduire la discipline "un fichier, un défaut" qui a fait ses preuves, pas le niveau de diagnostic manuel.
- 5 tentatives maximum est un choix pragmatique (validé par l'utilisateur) — pourrait s'avérer trop bas ou trop haut selon les types de projets rencontrés ; ajustable sans changement d'architecture (`-MaxAttempts`).
- Le ciblage fichier par heuristique (§2) peut se tromper sur des projets à structure inhabituelle (plusieurs fichiers HTML, JS inline sans `<script src>`) — dégrade gracieusement vers le comportement actuel (pas de ciblage, ou `not_verified`) plutôt que de planter.
