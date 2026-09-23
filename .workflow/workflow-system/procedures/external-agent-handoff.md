# Handoff vers un agent externe

Codex remplit le contrat avant d'appeler GLM ou Claude.

## Avant l'envoi

- spec ou ticket approuvé ;
- base SHA et branche identifiés ;
- fichiers autorisés listés ;
- commandes de test connues ;
- secrets exclus ;
- objectif unique et vérifiable.

## Handoff GLM

GLM reçoit la mission d'implémentation, les contraintes, les tests obligatoires et le format evidence-bundle. Il crée code/tests/commit, mais ne merge pas et ne s'approuve pas.

## Handoff Claude

Claude reçoit la spec, le diff, les résultats et le contexte pertinent. Il ne modifie pas la branche. Il retourne APPROVED ou CHANGES_REQUIRED avec des findings reproductibles.

Toute correction après revue recommence par GLM puis repasse par Claude.
