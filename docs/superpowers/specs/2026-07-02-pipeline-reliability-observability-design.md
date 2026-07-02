# Fiabilité et observabilité de l'infrastructure ControlTower — Sous-projet 4

**Date:** 2026-07-02
**Status:** Approved
**Origine:** Retour d'expérience de la création réelle de "Neon Paddle" (jeu Pong) via Ornith/Aider : le pipeline a rapporté `passed` deux fois pour un jeu fonctionnellement cassé, un test PowerShell préexistant s'est révélé non hermétique (dépend de l'état réel de la mémoire Hermes du poste), et une question légitime a été soulevée sur la configuration de service du modèle Ornith.

## Contexte programme (roadmap complète, pour référence)

Cette session a identifié 4 sous-projets indépendants pour rendre ControlTower robuste au développement réel, peu importe le modèle LLM branché :

1. **Moteur de vérification fonctionnelle** — un vrai contrôle d'exécution (pas seulement structurel), exposé comme statut distinct de la validation structurelle.
2. **Boucle d'auto-correction / renforcement Hermes** — découpage automatique des corrections multi-points en passes ciblées, retry automatique, pondération des patterns qui marchent.
3. **UX webapp** — bouton "Corriger ce projet" en Création, badges de statut explicites, capture d'écran du smoke-test dans l'UI.
4. **Fiabilité et observabilité de l'infrastructure** (CE DOCUMENT) — hygiène d'encodage, mémoire Hermes testable de façon hermétique, observabilité de la santé du service modèle.

Chaque sous-projet garde son propre cycle spec → plan → implémentation. Seul le sous-projet 4 est détaillé ici.

### Principes transverses (s'appliquent à TOUS les sous-projets, pas seulement au 4)

- **Configurabilité explicite dans l'UI** : tout paramètre technique ajusté par le pipeline (racine mémoire Hermes, modèle utilisé, etc.) doit être visible et, quand c'est pertinent pour l'utilisateur, configurable depuis l'interface webapp — jamais un réglage caché uniquement dans un script.
- **Généralisation, pas sur-ajustement** : aucune règle, aucun correctif de pipeline ne doit être écrit en pensant à un projet particulier (Neon Paddle ou autre) — chaque règle doit être formulée et testée de façon générique, applicable à n'importe quelle future demande de création/audit/correction.
- **Renforcement anti-faux-positif** : aucune information ne doit être promue en mémoire Hermes comme acquise ("success", "passed") sans une vérification qui le justifie réellement.
- **UX explicite en permanence** : l'utilisateur doit toujours pouvoir dire ce qui se passe (statut clair, pas d'état ambigu ou silencieux).

## Objectif (Sous-projet 4)

Fermer trois dettes découvertes en conditions réelles aujourd'hui : (a) des lectures de fichiers PowerShell non forcées en UTF-8 pouvant produire de faux positifs de mojibake, (b) une mémoire Hermes non isolable pour les tests, rendant la suite de tests PowerShell non hermétique, (c) aucune observabilité sur la santé de service du modèle LLM configuré (renderer/template Ollama, absence de boucle de répétition) — alors que c'est exactement la classe de bug qu'un changement de modèle futur pourrait réintroduire silencieusement.

## Non-goals

- Pas de sélecteur de modèle dans l'UI (rester sur `ollama_chat/ornith:9b` codé en dur comme aujourd'hui) — c'est un morceau plus large, hors périmètre hygiène, à traiter dans un sous-projet dédié si besoin.
- Pas de vérification fonctionnelle des projets générés (Sous-projet 1).
- Pas de découpage automatique des corrections multi-fichiers (Sous-projet 2).

## Contexte gathered

- 34 appels `Get-Content ... -Raw` sans `-Encoding` dans 21 scripts de `tools/*.ps1` (hors `tools/tests/`, qui lit surtout ses propres fixtures/sources ASCII et présente un risque négligeable).
- `Start-AiderAudit.ps1`, `Start-AiderCreation.ps1`, `Start-AiderFix.ps1` codent en dur le chemin `hermes_memory/central/guidance_cache.md` relatif à leur propre script — aucun des trois pipelines (`Invoke-Aider{Audit,Fix,Creation}Pipeline.ps1`) ni `Invoke-ControlTowerRun.ps1` (qui a pourtant déjà un paramètre `-HermesMemoryRoot` en surface) ne le leur transmet.
- `Test-AiderCreationReliability.ps1` échoue ou réussit selon l'état de la vraie mémoire Hermes globale du poste au moment du run (vérifié empiriquement : échec reproductible avant que la session ne peuple `guidance_cache.md` via de vrais runs, succès après) — dépendance cachée, non hermétique.
- `ollama show ornith:9b --modelfile` affiche `TEMPLATE {{ .Prompt }}` (passthrough brut) mais aussi `RENDERER ornith` et `PARSER ornith`. Un appel direct à `POST /api/chat` (Ollama 0.30.11) confirme que la réponse sépare correctement `thinking` de `content`, sans boucle de répétition, avec les paramètres d'échantillonnage recommandés (temperature 0.6, top_p 0.95, top_k 20) déjà actifs par défaut. Conclusion : notre installation n'est **pas** affectée par le bug de template signalé publiquement sur ce modèle, mais rien ne le vérifie automatiquement — un futur changement de modèle ou de version d'Ollama pourrait réintroduire ce problème silencieusement.
- `Test-ControlTowerDependencies.ps1` a déjà un paramètre `-HermesMemoryRoot` et est déjà appelé à chaque `GET /api/state` (donc à chaque affichage/rafraîchissement de l'UI) — c'est le point d'intégration existant pour toute nouvelle vérification "légère" qui doit rester visible sans ralentir l'UI.
- `build_commands()` dans `app.py` est le point d'intégration existant pour toute nouvelle action "à la demande" déclenchable depuis l'UI (réutilise tout le système de jobs/logs déjà en place).

## Design

### 1. Lint d'encodage permanent

**Nouveau fichier** `tools/tests/Test-PowerShellEncodingLint.ps1` : scanne tous les `.ps1` sous `tools/` à l'exclusion de `tools/tests/`, repère par regex tout `Get-Content` utilisé avec `-Raw` sans `-Encoding` explicite sur la même instruction logique, échoue en listant chaque `fichier:ligne` en violation. Ajouté à `tools/tests/Invoke-ControlTowerTestSuite.ps1`.

### 2. Correction des 34 sites d'appel

`-Encoding UTF8` ajouté uniformément sur les 34 appels identifiés dans les 21 fichiers listés en Contexte — y compris les lectures de JSON internes (config, baseline, manifestes), pour garder une règle simple et sans exception à mémoriser plutôt qu'un tri par risque perçu.

### 3. `-HermesMemoryRoot` configurable de bout en bout

- `Start-AiderAudit.ps1`, `Start-AiderCreation.ps1`, `Start-AiderFix.ps1` : nouveau paramètre `[string]$HermesMemoryRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "hermes_memory")` (valeur par défaut = comportement actuel, zéro régression), remplace le chemin codé en dur pour la lecture de `guidance_cache.md`.
- `Invoke-AiderAuditPipeline.ps1`, `Invoke-AiderFixPipeline.ps1`, `Invoke-AiderCreationPipeline.ps1` : même paramètre avec même valeur par défaut, transmis au `Start-Aider*.ps1` correspondant.
- `Invoke-ControlTowerRun.ps1` : ajoute `HermesMemoryRoot = $HermesMemoryRoot` dans `$auditArgs`, `$fixArgs`, `$creationArgs` (le paramètre existe déjà en surface, seule la transmission manquait).

### 4. Tests de fiabilité rendus hermétiques

`Test-AiderCreationReliability.ps1`, `Test-AiderReliabilityLayer.ps1`, `Test-AiderFixReliability.ps1` : chacun crée sa propre mémoire Hermes isolée sous son `hermes_lab\...` de test (`Initialize-HermesMemory.ps1 -MemoryRoot <fixture>` puis `Add-HermesMemoryEntry.ps1` avec un contenu connu), passe `-HermesMemoryRoot <fixture>` à son appel `Invoke-Aider*Pipeline.ps1`, et vérifie ce contenu précis et déterministe (au lieu de `Contains("Hermes central guidance")` sur un contenu non maîtrisé). Aucun test ne doit plus lire ni écrire dans la vraie mémoire Hermes globale du poste.

### 5. Observabilité de la santé du service modèle — vérification légère (automatique)

`Test-ControlTowerDependencies.ps1` gagne une fonction `Test-OllamaServingHealth -ModelName <nom>` (paramétrée, pas câblée en dur sur "ornith") : exécute `ollama show <model> --modelfile`, détecte le motif exact du bug connu (ligne `TEMPLATE` = `{{ .Prompt }}` strict ET aucune ligne `RENDERER` présente) → statut `"warning"` avec message explicite ; sinon `"ok"`. Aucun appel réseau/génération — reste rapide, s'exécute à chaque `GET /api/state`, donc visible automatiquement dans le panneau de dépendances existant de l'UI sans code UI nouveau.

### 6. Observabilité de la santé du service modèle — vérification live (à la demande)

**Nouveau script** `tools/Test-ModelServingHealth.ps1 -ModelName <nom>` : envoie une requête `POST /api/chat` déterministe et courte (ex. "écris juste `def add(a, b): return a + b`, sans explication") au modèle configuré, avec un timeout (60s). Valide : réponse reçue, `done_reason = "stop"` (pas `"length"`, signe de dérive), absence de boucle de répétition (heuristique : une sous-chaîne de 15+ caractères qui se répète 3 fois ou plus consécutivement). Résultat structuré en JSON (même format que les autres scripts `Test-*`).

Exposé dans l'UI via une nouvelle entrée dans `build_commands()` (`app.py`) : `"model_health_check"` (groupe "Modele" ou "Systeme", `dangerous: false`, `template: false`) qui réutilise entièrement le système de jobs/logs déjà en place — zéro nouveau code UI, juste une nouvelle commande dans la liste existante. L'utilisateur déclenche le contrôle live quand il le souhaite ; il n'est jamais lancé automatiquement (coût en temps/latence trop élevé pour tourner à chaque chargement de page).

## Testing / verification plan

- `powershell -File tools/tests/Test-PowerShellEncodingLint.ps1` : 0 violation.
- `powershell -File tools/tests/Invoke-ControlTowerTestSuite.ps1` : suite complète verte, y compris les 3 tests de fiabilité rendus hermétiques, sans dépendre ni écrire dans la vraie mémoire Hermes globale.
- `python -m pytest apps/controltower-ui/tests` : la nouvelle commande `model_health_check` apparaît dans `/api/state`.
- Vérification manuelle : `tools/Test-ModelServingHealth.ps1 -ModelName "ornith:9b"` retourne un statut `ok` sur l'installation actuelle (confirme empiriquement ce qui a déjà été vérifié en direct pendant le brainstorming).

## Risks / open questions

- L'heuristique de détection de boucle (sous-chaîne de 15+ caractères répétée 3+ fois) est un choix pragmatique, pas une preuve formelle d'absence de dérive — acceptable pour un contrôle de fumée, pas pour une garantie de qualité (rôle du Sous-projet 1).
- Le nom du modèle reste codé en dur ailleurs dans le code (`app.py`, `Invoke-ControlTowerRun.ps1`) — accepté comme non-goal explicite pour ce sous-projet, mais noté pour un futur sous-projet de sélection de modèle en UI.
