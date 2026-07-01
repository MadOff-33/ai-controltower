# UX/UI Audit and Final Consolidation Roadmap

Date: 2026-07-01

## Objectif

Cloturer AI ControlTower comme produit local utilisable, fiable et maintenable autour d'Aider/Ollama/Ornith, avec Hermes comme memoire centrale.

Ce document couvre:

- audit UX/UI du cockpit Flask;
- recette bout en bout;
- roadmap de consolidation finale;
- criteres de fermeture definitive.

## Methode

Grille appliquee:

- Superpowers: observation, verification avant conclusion, evidence first.
- BMAD adapte: Business, Methode, Architecture, Delivery.

BMAD n'est pas installe comme skill callable dans cet environnement. La grille est donc appliquee comme cadre d'analyse.

## Synthese Executive

Le projet est proche d'une V1 cloturable. Les couches critiques existent:

- audit fiable par snapshot et context pack;
- correction bornee par ticket;
- validation post-run;
- memoire centrale Hermes;
- cockpit Flask local;
- tests automatises;
- documentation d'usage.

Les principaux points restants ne sont plus des fondations manquantes, mais des consolidations produit:

1. Rendre le cockpit plus explicite sur les etapes `dry-run`, `audit reel`, `ticket`, `fix`.
2. Ajouter une vraie gestion de run asynchrone cote UI pour les commandes longues.
3. Produire un rapport final de recette machine lisible par l'utilisateur.
4. Ajouter un parcours guide audit -> rapport -> ticket -> fix.
5. Verrouiller l'installation et la distribution Windows.

## Audit UX/UI

### Ce qui fonctionne

- L'interface demarre localement via `apps/controltower-ui/ControlTower.cmd`.
- La page principale affiche directement l'outil, sans landing page inutile.
- Le chemin projet est visible et modifiable.
- Git, branche et GitHub sont detectes.
- Les dependances principales sont affichees.
- Le catalogue expose les actions utiles.
- Le chat/log permet un pilotage simple par mots-clefs.
- Les actions reelles demandent confirmation cote API.
- Les commandes non autorisees sont refusees.
- La zone chat/log est maintenant prioritaire en largeur et hauteur sur desktop.
- Pas de debordement horizontal observe sur viewport mobile.

### Points UX a consolider

#### UX-1: Clarifier le statut des runs

Probleme: l'utilisateur peut confondre `Audit dry-run` avec un audit produit par Aider.

Etat actuel: le statut `structure-passed` existe et corrige le faux succes.

Consolidation:

- afficher un badge distinct dans l'UI:
  - `Preparation OK`;
  - `Audit reel requis`;
  - `Audit valide`;
  - `Validation bloquee`;
- afficher une phrase courte dans le log quand `Draft report: True`.

Priorite: P0.

#### UX-2: Transformer le catalogue en parcours guide

Probleme: les commandes existent, mais l'utilisateur doit comprendre l'ordre.

Consolidation:

- ajouter un rail "Parcours recommande":
  1. Selectionner projet;
  2. Verifier dependances;
  3. Audit dry-run;
  4. Audit reel;
  5. Creer ticket;
  6. Fix dry-run;
  7. Fix reel;
  8. Validation finale.

Priorite: P0.

#### UX-3: Gestion des commandes longues

Probleme: `tests complets`, `audit reel` et `fix reel` peuvent bloquer l'appel HTTP et rendre l'UI peu lisible.

Consolidation:

- introduire des jobs locaux:
  - `POST /api/jobs`;
  - `GET /api/jobs/<id>`;
  - stream ou polling du log;
  - etat `queued/running/succeeded/failed/cancelled`.

Priorite: P0.

#### UX-4: Correction par ticket encore trop template

Probleme: les commandes fix affichent `<WORKSPACE_PATH>` et `<TICKET_PATH>`.

Consolidation:

- ajouter un selecteur de workspace recent;
- ajouter un selecteur de ticket existant;
- ajouter un bouton "Creer ticket depuis rapport" quand un rapport d'audit existe.

Priorite: P1.

#### UX-5: Mobile fonctionnel mais pas optimal

Probleme: sur mobile, le chat arrive apres dependances et catalogue. Le cockpit est utilisable, mais le log est trop bas.

Consolidation:

- passer l'ordre mobile a:
  1. projet;
  2. chat/log;
  3. parcours recommande;
  4. dependances;
  5. catalogue avance.

Priorite: P1.

#### UX-6: Etats d'erreur encore techniques

Probleme: les erreurs PowerShell/Aider peuvent etre brutes.

Consolidation:

- classer les erreurs:
  - dependance manquante;
  - projet introuvable;
  - pack trop gros;
  - validation bloquee;
  - Aider/Ollama indisponible;
  - action refusee par garde-fou;
- proposer la prochaine action concrete.

Priorite: P1.

## Audit UI

### Points forts

- Style sobre, adapte a un outil operationnel.
- Palette claire, non decorative.
- Panels lisibles et peu distrayants.
- Boutons de commande compacts depuis l'ajustement UX.
- Zone log sombre utile pour distinguer la sortie machine.

### Points a ameliorer

- Ajouter des icones simples aux actions frequentes:
  - rafraichir;
  - lancer;
  - afficher template;
  - ouvrir GitHub;
  - verifier.
- Rendre les badges de dependances plus lisibles avec espaces visuels entre label et statut.
- Ajouter un bandeau de statut global du dernier run.
- Ajouter une zone "dernier workspace" avec liens vers:
  - context pack;
  - rapport;
  - validation;
  - run log.
- Remplacer les boutons generiques `Lancer` par des libelles d'action plus explicites sur les actions dangereuses.

## Audit Architecture Produit

### Solide

- Les scripts PowerShell restent le moteur fiable.
- Flask est une couche de pilotage, pas le coeur critique.
- Les chemins avec espaces sont couverts.
- Les snapshots protegent le projet cible.
- Les validations detectent fichiers non autorises, marqueurs fantomes et rapport squelette.
- Hermes conserve l'experience transverse.

### A consolider

- L'UI doit consommer des statuts structures plutot que parser du texte.
- Les jobs longs doivent etre persistants et consultables.
- Le lien audit -> ticket -> fix doit devenir un workflow guide.
- Le rapport final de run doit etre un artefact stable, pas seulement une sortie console.
- Les donnees locales doivent etre clairement separees des fichiers versionnes.

## Recette Bout En Bout

### Pre-requis

- Windows avec PowerShell 5.1.
- Git disponible.
- Python disponible via `py -3` ou `python`.
- Ollama installe.
- Modele `ornith:9b` present dans Ollama.
- Aider installe.
- Projet cible existant.

### Commandes de verification de base

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\tests\Invoke-ControlTowerTestSuite.ps1"
```

Resultat attendu:

- 6 suites executees;
- exit code 0;
- aucun artefact persistant dans `hermes_lab/` hors `.gitkeep`.

### Recette UI

1. Lancer:

```cmd
C:\AI_ControlTower\apps\controltower-ui\ControlTower.cmd
```

2. Ouvrir `http://127.0.0.1:8765`.

3. Saisir le projet cible.

4. Verifier:

- branche Git affichee si repo Git;
- URL GitHub affichee si remote GitHub;
- dependances visibles;
- catalogue charge;
- chat/log visible.

5. Dans le chat, saisir:

```text
git
```

Resultat attendu:

- le champ se vide;
- le log affiche `Git status`;
- aucune modification du projet.

6. Cliquer `Fix dry-run depuis ticket`.

Resultat attendu:

- aucune execution dangereuse;
- le log affiche la commande template avec `<WORKSPACE_PATH>` et `<TICKET_PATH>`.

7. Tenter une action reelle comme `Audit reel avec Aider`.

Resultat attendu:

- confirmation demandee avant execution.

### Recette Audit

1. Lancer un dry-run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "D:\Dev\AUDIT\AUDIT-NETWORKSENTINEL" -ValidateAfterDryRun
```

Resultat attendu:

- workspace cree dans `C:\AI_ControlTower\audits`;
- snapshot cree;
- inventaire cree;
- context pack cree;
- `Chars` inferieur ou egal a la limite;
- `Draft report: True`;
- statut final `structure-passed`;
- Hermes ajoute une experience de preparation, pas un faux succes.

2. Lancer l'audit reel:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Audit -ProjectPath "D:\Dev\AUDIT\AUDIT-NETWORKSENTINEL" -RunAider
```

Resultat attendu:

- Aider est lance;
- le rapport est ecrit uniquement dans `reports/`;
- validation post-run executee;
- statut final `passed` ou `failed`;
- aucun fichier non autorise cree ou modifie.

### Recette Fix

1. Creer un ticket explicite:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\New-AiderFixTicket.ps1" -WorkspacePath "<WORKSPACE>" -TicketId "fix_example" -Title "Titre" -Goal "Objectif" -EditableFiles @("chemin/relatif.py")
```

2. Lancer fix dry-run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Fix -WorkspacePath "<WORKSPACE>" -TicketPath "<TICKET>" -ValidateAfterDryRun
```

3. Lancer fix reel:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\AI_ControlTower\tools\Invoke-ControlTowerRun.ps1" -Mode Fix -WorkspacePath "<WORKSPACE>" -TicketPath "<TICKET>" -RunAider
```

Resultat attendu:

- seuls les fichiers autorises par ticket changent dans `source_snapshot/`;
- les commandes de verification du ticket passent ou le run est bloque;
- le projet cible original n'est jamais modifie automatiquement.

## Roadmap De Consolidation Finale

### Phase 1: UX de statut et parcours guide

Etat: implemente V1.

Objectif: empecher toute confusion entre preparation, audit reel et validation.

Livrables:

- badge dernier run;
- libelles `Preparation OK`, `Audit reel requis`, `Audit valide`, `Bloque`;
- rail de parcours recommande;
- liens vers dernier workspace, rapport, validation et log.

Critere de sortie:

- un utilisateur peut savoir quoi faire ensuite sans lire la console.

### Phase 2: Jobs asynchrones UI

Etat: implemente V1.

Objectif: rendre le cockpit robuste pour les commandes longues.

Livrables:

- API jobs;
- log live ou polling;
- etat running/succeeded/failed;
- bouton annuler quand possible;
- historique des derniers runs.

Critere de sortie:

- un audit reel peut tourner sans bloquer l'interface.

### Phase 3: Workflow ticket/fix guide

Etat: implemente V1 pour la creation de ticket depuis rapport et les templates fix.

Objectif: rendre la correction autonome mais bornee.

Livrables:

- liste des workspaces recents;
- liste des rapports;
- creation assistee de ticket depuis rapport;
- selection ticket dans l'UI;
- lancement fix dry-run/fix reel sans template manuel.

Critere de sortie:

- l'utilisateur peut passer d'un rapport a une correction bornee sans construire la commande a la main.

### Phase 4: Rapport final de run

Etat: implemente V1.

Objectif: chaque run produit un artefact humain lisible.

Livrables:

- `run_summary.md`;
- statut;
- commandes executees;
- chemins utiles;
- validations;
- anomalies;
- prochaines actions.

Critere de sortie:

- l'utilisateur peut ouvrir un seul fichier pour comprendre le run.

### Phase 5: Packaging Windows

Etat: implemente V1.

Objectif: rendre l'installation propre et stable.

Livrables:

- lanceur racine `ControlTower.cmd`;
- verification Python/Aider/Ollama au demarrage;
- documentation courte d'installation;
- option reset local state;
- version affichee dans l'UI.

Critere de sortie:

- un nouveau poste peut lancer le cockpit sans connaitre l'arborescence interne.

## Critere De Cloture Definitive

Le projet peut etre ferme quand les criteres suivants sont vrais:

- suite complete verte;
- recette UI passee;
- recette audit dry-run passee;
- recette audit reel passee sur un projet cible;
- recette fix passee avec ticket;
- aucun changement non autorise dans le projet cible;
- Hermes contient au moins une lecon utile issue d'un run reel;
- README, manuel, architecture, checklist et closure report alignes;
- dernier commit pousse sur `main`;
- `git status` propre.

## Decision

Etat actuel: cloturable techniquement, mais pas encore definitif produit.

Recommendation: terminer les phases 1 a 4 avant fermeture finale. La phase 5 peut etre incluse si l'objectif est une distribution vraiment confortable sur un autre poste Windows.
