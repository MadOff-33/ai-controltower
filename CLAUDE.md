# CLAUDE.md â€” ai-controltower

## Workflow obligatoire

<!-- UNIVERSAL_RESUME_RULES_START -->
### Reprise de projet

Pour une demande de reprise :
1. résoudre le worktree actif avant de lire le contexte métier ;
2. dans le worktree retenu, reconstituer l'état réel depuis `CONTEXT.md`, `.workflow/state.yaml` et les sources de vérité pertinentes ;
3. laisser le ROUTER, les skills chargés et les agents déterminer dynamiquement la suite logique ;
4. présenter cette suite et le gate applicable avant toute nouvelle action technique.

Une reprise seule ne déclenche ni test, build, installation, diagnostic ni correction. Un projet ou POC n'est terminé que sur déclaration explicite de l'utilisateur.
<!-- UNIVERSAL_RESUME_RULES_END -->

Avant toute tÃ¢che :
1. ouvrir `.workflow/workflow-system/WORKFLOW.md` ;
2. charger `using-superpowers/SKILL.md` depuis `.claude/skills/` ;
3. exÃ©cuter `.workflow/workflow-system/procedures/00-session-preflight.md` ;
4. suivre `.workflow/workflow-system/ROUTER.md` ;
5. charger rÃ©ellement les `SKILL.md` sÃ©lectionnÃ©s par la route ;
6. lire ensuite `CONTEXT.md` et les spÃ©cifications pertinentes.

Ne jamais exposer de secret. VÃ©rifier les rÃ©sultats avant de dÃ©clarer une tÃ¢che terminÃ©e.
