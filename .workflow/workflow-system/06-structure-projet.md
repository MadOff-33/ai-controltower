# 06 — Structure du projet cible

~~~text
projet/
├── AGENTS.md
├── CLAUDE.md                         # si utilisé par Claude
├── CONTEXT.md
├── README.md
├── .gitignore
│
├── .workflow/
│   ├── project-manifest.yaml
│   └── state.yaml
│
├── docs/
│   ├── adr/
│   ├── research/
│   ├── specs/
│   ├── plans/
│   └── reviews/
│
├── _bmad/                            # installation BMAD native
├── _bmad-output/                     # artefacts BMAD
│
├── .ci/notion_sync/                  # synchronisation existante vers Notion
├── .github/workflows/notion-sync.yml # déclenchement GitHub Actions
├── project_manifest.yaml             # projection attendue par le sync Notion
│
├── 04-contracts/                     # contrats de handoff et de preuve
├── 05-adapters/                      # formats par agent
├── procedures/                       # gates propres à ce workflow
├── VERSION.lock                      # versions validées du workflow
│
└── _workflow-artifacts/
    ├── evidence/
    └── handoffs/
~~~

## Modèle de chargement pour un LLM

Le LLM lit dans cet ordre :

~~~text
workflow-system/WORKFLOW.md
→ workflow-system/MANIFEST.yaml
→ workflow-system/ROUTER.md
→ route sélectionnée
→ contrat correspondant
→ rôle de l'agent
~~~

Il ne charge pas toutes les skills à chaque session.

## Installation native ou portable

- **Native** : BMAD et Superpowers restent installés dans les emplacements attendus par l'agent ; le dossier universel contient le routeur et les adaptateurs.
- **Portable** : le dossier universel contient les instructions Markdown nécessaires à Aider ou à un LLM local.

Ne pas copier des logs, caches, transcripts, tokens ou secrets dans ce dossier.
