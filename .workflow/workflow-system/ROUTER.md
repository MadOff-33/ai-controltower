# ROUTER.md — Choix du workflow

## R0 — Recherche, analyse ou documentation

```text
preflight
  → Matt: research ou BMAD: bmad-deep-recon
  → rapport sourcé
  → vérification des sources
  → archivage
```

## R1 — Prototype ou faisabilité

```text
preflight
  → Matt: prototype
  → prototype jetable
  → conclusion
```

Le prototype n'est pas du code de production.

## R2 — Petite modification clairement définie

```text
preflight
  → brainstorming léger et validation
  → using-git-worktrees
  → GLM: TDD + implémentation
  → Claude: revue indépendante
  → Codex: vérification + Git
```

## R3 — Fonctionnalité moyenne ou refactorisation multi-fichiers

```text
preflight
  → grill-with-docs
     → grilling + domain-modeling
  → to-spec
  → to-tickets
  → writing-plans
  → using-git-worktrees
  → handoff GLM
  → evidence bundle
  → revue Claude
  → vérification Codex
  → merge ou PR
```

## R4 — Nouveau produit, architecture ou projet à risque

```text
preflight
  → bmad-deep-recon             optionnel
  → bmad-product-brief          optionnel
  → bmad-prd
  → bmad-ux                     optionnel
  → bmad-architecture
  → TEA: test-design             si risque élevé
  → bmad-create-epics-and-stories
  → bmad-sprint-planning        gate de readiness
  → writing-plans par story
  → worktree
  → GLM
  → Claude: revue indépendante
  → TEA: test-review/trace      si TEA activé
  → Codex: vérification + Git
  → bmad-retrospective
```

## R5 — Bug, erreur ou échec de test

```text
preflight
  → diagnosing-bugs
  → systematic-debugging
  → plan si plusieurs fichiers
  → worktree
  → test de régression par GLM
  → correction
  → revue Claude
  → vérification Codex
```

## Règles de non-cumul

- BMAD `bmad-create-epics-and-stories` et Matt `to-tickets` ne doivent pas produire deux découpages concurrents.
- Superpowers `subagent-driven-development` n'est pas utilisé dans la chaîne principale : il serait en conflit avec GLM et Claude externes.
- `bmad-build-auto` n'est pas utilisé par défaut : il suppose un modèle d'exécution autonome et des sous-agents disponibles.
- TEA est activé pour R4 ou pour un besoin explicite de stratégie de tests, NFR ou traçabilité.
- Les noms BMAD de cette route suivent la génération actuelle : bmad-build, bmad-project-context, bmad-review et bmad-sprint-planning.
