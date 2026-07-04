# Synchro Notion automatique — CJD_DEV

Ce dossier fait remonter l'état du projet dans Notion (Knowledge OS)
**automatiquement**, via GitHub Actions. Ça tourne chez GitHub : ton PC peut
être éteint.

## Ce qui se passe
- À chaque `push` sur `main` **et** une fois par jour (06:00 UTC), GitHub :
  1. récupère le repo,
  2. lit `project_manifest.yaml` + l'état git,
  3. détecte la **présence** des fichiers sensibles (jamais leur contenu),
  4. **met à jour** les pages Notion existantes (par leur clé) ou en crée si absentes,
  5. écrit une ligne dans la base **Journal de synchronisation** (qui / quand / commit).

## Garde-fous
- Aucun secret n'est lu ni stocké (`.env`, `settings.json`, clés → présence seulement).
- Les champs `password`, `token`, `secret`, `api_key`, `consumer_secret`,
  `private_key` sont masqués : `[SECRET REDACTED]`.
- Le **Statut** des décisions et des risques n'est écrit qu'à la création :
  si tu valides une décision ou fermes un risque **dans Notion**, la synchro
  ne l'écrase jamais.

## Mise en route (une seule fois) — étape à faire par Michael
La synchro a besoin d'un **jeton d'intégration Notion**, stocké comme *secret*
GitHub nommé `NOTION_TOKEN`. Voir la procédure guidée pas à pas fournie par
Claude. Résumé :

1. Créer une intégration interne sur https://www.notion.so/my-integrations
   (type *Internal*, capacités : lecture + insertion + mise à jour de contenu).
2. Copier le jeton `ntn_...` / `secret_...`.
3. Dans Notion, ouvrir la page **Knowledge OS** → menu `•••` → *Connexions* →
   ajouter l'intégration (elle hérite alors de l'accès aux 7 bases).
4. Dans GitHub : repo CJD_DEV → *Settings* → *Secrets and variables* → *Actions*
   → *New repository secret* → nom `NOTION_TOKEN`, valeur = le jeton.
5. Déclencher une première fois : onglet *Actions* → *Notion Knowledge Sync* →
   *Run workflow*.

## Tester en local (facultatif, sans rien envoyer)
```bash
cd .ci/notion_sync
pip install pyyaml requests
DRY_RUN=true python sync.py     # affiche le plan, n'envoie rien
```

## Ajouter un nouveau projet
Réutiliser ce dossier `.ci/notion_sync/` dans l'autre repo, adapter
`project_manifest.yaml`, et garder le même `notion_databases.yml` (les bases
Notion sont communes à tous les projets).
