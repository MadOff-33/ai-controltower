# Roadmap de suite — après la boucle d'auto-correction et le renforcement Hermes

Date: 2026-07-02

## Contexte

Les 4 sous-projets du roadmap précédent (`docs/ux_ui_audit_and_final_roadmap.md`) sont livrés, ainsi que le fix `Invoke-AiderAuditContinuation.ps1` et le nettoyage git. Le retour d'expérience du 2026-07-02 a identifié 6 limites réelles, non bloquantes, mais qui méritent d'être traitées avant de considérer la boucle d'auto-correction comme définitivement fiable en production. Ce document les transforme en candidats de travail priorisés, prêts à être passés individuellement par `superpowers:brainstorming` quand le moment sera venu — aucun n'a encore été discuté avec l'utilisateur, donc aucun n'est un spec approuvé.

## Priorité P0 — à faire avant de faire confiance à la boucle

### A. Validation réelle contre Ornith/Aider

**Problème :** toute la boucle d'auto-correction (`tools/Invoke-AutoCorrectionLoop.ps1`) a été testée uniquement contre des scripts Aider factices (`fake-aider-*.ps1`). L'hypothèse centrale du design — qu'une consigne mono-fichier, mono-défaut, en langage naturel généré automatiquement, suffit à faire réussir Ornith 9B de façon fiable — n'a jamais été vérifiée en conditions réelles.

**Pourquoi ça compte :** c'est exactement le type de risque que Neon Paddle avait révélé (Ornith réussit sur consigne exacte mono-fichier, échoue silencieusement sur consigne multi-points). Si les briefs générés automatiquement par `Build-CorrectionBrief` ne sont pas aussi précis qu'un brief écrit à la main, la boucle pourrait épuiser ses 5 tentatives sans jamais corriger, ou pire, halluciner un "fixed" sur un cas limite non couvert par les tests actuels.

**Ce que ça implique concrètement :** pas de nouveau code — relancer une création volontairement cassée (même patron que Neon Paddle) via l'UI, laisser la boucle tourner en conditions réelles, observer si elle corrige effectivement, et si les briefs générés sont compris par Ornith aussi bien que des briefs manuels. Ajuster `Build-CorrectionBrief` si les résultats montrent que le langage généré n'est pas assez directif.

**Dépendances :** aucune, peut se faire immédiatement.

## Priorité P1 — cohérent avec les objectifs déjà exprimés

### B. Paramétrage exposé dans l'UI

**Problème :** `-HermesMemoryRoot`, `-MaxAttempts` (fixé à 5), le modèle Ollama utilisé, et les templates de `Build-CorrectionBrief` sont tous en dur côté PowerShell. Rien n'est configurable depuis l'interface.

**Pourquoi ça compte :** c'est une demande explicite et répétée depuis le début de ce cycle de travail ("tout ce qui est paramétrable [doit] pouvoir l'être dans l'interface utilisateur et être explicite").

**Piste d'approche à discuter :** un panneau "Réglages avancés" dans l'UI (nombre de tentatives, chemin mémoire Hermes, modèle par mode Audit/Fix/Creation), avec des valeurs par défaut sûres et une confirmation explicite avant tout changement qui affecte un run réel.

**Dépendances :** aucune techniquement, mais gagnerait à suivre l'item A pour savoir si `MaxAttempts=5` est réellement le bon défaut.

### C. Renforcement Hermes décisionnel, pas seulement informatif

**Problème :** le taux de réussite par type de défaut calculé par `Get-HermesGuidance.ps1` est injecté dans le prompt d'Aider mais n'influence aucune décision côté pipeline — rien ne raccourcit la boucle sur un type de défaut historiquement jamais corrigé, rien ne l'allonge sur un type historiquement fiable.

**Pourquoi ça compte :** c'est la différence entre "Hermes qui se souvient" et "Hermes qui apprend réellement" — l'objectif énoncé depuis le début du cycle.

**Piste d'approche à discuter :** avant de lancer une tentative, consulter le taux de réussite du type de défaut concerné ; si le taux est à 0% sur un échantillon suffisant, réduire les tentatives ou signaler explicitement à l'utilisateur que ce type de défaut a un historique de correction automatique infructueux plutôt que de gaspiller du temps de calcul.

**Dépendances :** demande plus de données réelles pour être calibré (voir item A) — prématuré sans quelques dizaines d'entrées `correction_attempt` réelles en mémoire.

### D. Timeout et annulation de la boucle

**Problème :** une fois lancée, la boucle peut tourner plusieurs minutes (jusqu'à 5 appels Aider réels) sans qu'aucun mécanisme d'annulation propre n'existe côté UI au-delà de tuer le processus.

**Pourquoi ça compte :** contredit l'objectif "l'utilisateur doit toujours savoir ce qu'il se passe" — un utilisateur bloqué devant une boucle qui semble figée n'a aucun levier explicite.

**Piste d'approche à discuter :** réutiliser le système de jobs asynchrones déjà existant côté UI (voir `docs/ux_ui_audit_and_final_roadmap.md`, Phase 2) pour exposer un bouton "Annuler" pendant une boucle de correction, plus un timeout global raisonnable par tentative.

**Dépendances :** aucune, indépendant des autres items.

## Priorité P2 — extensions de couverture, non urgentes

### E. Élargir la vérification fonctionnelle

**Problème :** le contrôle webapp s'arrête au chargement initial (pas d'interaction), le contrôle Python se limite à la compilation + tests existants (aucun smoke test si le projet n'a pas de tests).

**Pourquoi ça compte :** un statut "ok" peut aujourd'hui vouloir dire "compile et ne plante pas au chargement", pas "fonctionne réellement" — c'est un plancher assumé depuis le sous-projet 1, mais qui reste une vraie limite si l'ambition est un outil de développement de confiance.

**Piste d'approche à discuter :** scénarios d'interaction basiques configurables (clic sur un bouton, saisie dans un champ) pour les webapps ; smoke test générique (import + exécution d'une fonction principale si détectable) pour les projets Python sans suite de tests.

**Dépendances :** aucune, mais gros effort de conception pour rester générique (non-goal explicite du sous-projet 1 à revisiter).

### F. Support desktop/autres types de projet

**Problème :** les projets `desktop`/`other` restent `not_verified` par design, et la boucle d'auto-correction n'a aucune branche de ciblage pour eux même si une vérification existait.

**Pourquoi ça compte :** limite la couverture de l'outil aux projets webapp et Python uniquement.

**Piste d'approche à discuter :** dépend fortement de la stack desktop visée (Tkinter ? PyQt ? Electron ?) — probablement le item le moins prioritaire tant qu'aucun cas d'usage réel desktop ne s'est présenté.

**Dépendances :** aucune, mais faible valeur sans un cas d'usage concret.

## Recommandation de séquencement

1. **A** en premier — c'est une observation, pas un développement, et elle informe directement la calibration de B, C et D.
2. **B et D** ensuite, en parallèle si besoin — indépendants l'un de l'autre, tous deux alignés sur des objectifs déjà exprimés.
3. **C** une fois qu'il y a assez de données réelles issues de A pour calibrer les seuils.
4. **E et F** seulement si un besoin concret se présente — ce sont des extensions de périmètre, pas des corrections de défaut.

## Non-goals de ce document

- Ce n'est pas un spec approuvé — chaque item doit passer par `superpowers:brainstorming` avec l'utilisateur avant tout développement.
- Ne couvre pas de nouvelles fonctionnalités hors du périmètre déjà exploré (pas de nouveau mode, pas de nouveau type de projet non mentionné ici).
- Ne remet pas en cause les décisions déjà prises et livrées (fonctionnement de la boucle, format des entrées Hermes, contrat JSON du moteur de vérification).
