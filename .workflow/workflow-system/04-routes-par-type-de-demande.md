# 04 — Routes détaillées

## Route R0 — Recherche

~~~text
procedures/00-session-preflight
→ Matt: research ou BMAD: bmad-deep-recon
→ rapport avec sources
→ contrôle des citations
→ archivage dans docs/research/
~~~

Aucun code de production et aucun merge.

## Route R1 — Prototype

~~~text
procedures/00-session-preflight
→ Matt: prototype
→ prototype isolé
→ évaluation
→ décision : abandonner ou transformer en nouvelle demande
~~~

## Route R2 — Correction simple

~~~text
procedures/00-session-preflight
→ validation courte
→ using-git-worktrees
→ GLM: test + code minimal
→ revue Claude
→ verification-before-completion
→ finishing-a-development-branch
~~~

## Route R3 — Fonctionnalité moyenne

~~~text
procedures/00-session-preflight
→ grill-with-docs
   → grilling
   → domain-modeling
→ to-spec
→ to-tickets
→ writing-plans
→ using-git-worktrees
→ procedures/external-agent-handoff
→ GLM: TDD + implémentation
→ evidence-bundle
→ Claude: revue indépendante
→ corrections GLM si nécessaire
→ nouvelle revue Claude
→ Codex: vérification
→ finishing-a-development-branch
~~~

## Route R4 — Projet complexe

~~~text
procedures/00-session-preflight
→ bmad-project-context
→ bmad-deep-recon              optionnel
→ bmad-product-brief           optionnel
→ bmad-prd
→ bmad-ux                     optionnel
→ bmad-architecture
→ TEA: test-design              si risque élevé
→ TEA: framework                si infrastructure de test nouvelle
→ TEA: ci                       si pipeline CI nouveau
→ bmad-create-epics-and-stories
→ bmad-sprint-planning
→ writing-plans par story
→ using-git-worktrees
→ procedures/external-agent-handoff
→ GLM story par story
→ Claude: revue indépendante
→ TEA: test-review et trace     si TEA activé
→ Codex: vérification
→ merge/PR
→ bmad-retrospective
~~~

## Route R5 — Bug

~~~text
procedures/00-session-preflight
→ Matt: diagnosing-bugs
→ Superpowers: systematic-debugging
→ reproduction minimale
→ hypothèse vérifiée
→ test de régression
→ correction GLM
→ revue Claude
→ vérification Codex
~~~

## Route documentation technique

~~~text
procedures/00-session-preflight
→ contexte projet
→ recherche ou inspection
→ rédaction ciblée
→ revue de cohérence
→ vérification des commandes
→ commit documentaire
~~~
