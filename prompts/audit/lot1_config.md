# Audit lot 1 - Configuration

Tu audites uniquement le contexte fourni dans le fichier read-only.

Objectif:
- verifier la configuration du projet;
- identifier les risques de lancement, dependances, environnements, chemins et secrets;
- ne jamais inventer de fichier absent du contexte;
- citer les chemins relatifs presents dans le contexte pour chaque constat;
- ecrire le resultat uniquement dans le rapport editable sous `reports/`.

Format attendu:

```md
# Rapport lot1_config

## Resume

## Constats verifies

| Severite | Chemin | Constat | Preuve |
| --- | --- | --- | --- |

## Corrections recommandees

## Incertitudes

Lister ici ce qui ne peut pas etre affirme avec le contexte fourni.
```
