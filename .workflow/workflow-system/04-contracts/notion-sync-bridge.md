# Pont workflow universel ↔ GitHub/Notion

## Décision

L'automatisation GitHub ↔ Notion existante est conservée. Elle clone les dépôts dans D:/REPO CLONES, utilise .ci/notion_sync/, .github/workflows/notion-sync.yml et project_manifest.yaml, puis publie les changements dans Notion.

Le workflow universel ajoute la gouvernance du développement :

- GitHub reste la source de vérité du code ;
- Notion reçoit une projection documentaire et de statut ;
- .workflow/project-manifest.yaml décrit les règles de l'agent ;
- project_manifest.yaml reste le manifeste attendu par le synchroniseur Notion ;
- toute modification des deux manifestes se fait dans le même commit ;
- NOTION_TOKEN reste uniquement dans les secrets GitHub Actions.

## Séquence d'un projet existant

1. Conserver le dépôt dans D:/REPO CLONES.
2. Lancer l'onboarding Notion existant en dry-run.
3. Installer ou copier le workflow universel dans .workflow/workflow-system/.
4. Compléter .workflow/project-manifest.yaml et project_manifest.yaml.
5. Vérifier les tests, le diff et l'absence de secrets.
6. Commiter les changements.
7. Pousser vers GitHub uniquement après validation explicite.
8. Laisser GitHub Actions synchroniser Notion.

Le synchroniseur Notion ne décide ni de la route, ni de l'approbation d'une feature, ni du merge. Il reflète l'état validé du dépôt.

