# Superpowers Core — Adaptation Aider / Ornith

## Objectif

Utiliser les principes Superpowers dans Aider sans dépendre du plugin Claude Code.

## Règles générales

- Toujours commencer par clarifier la tâche.
- Choisir le workflow adapté avant de coder.
- Préférer les petites modifications vérifiables.
- Utiliser les tests comme filet de sécurité.
- Ne jamais déclarer terminé sans vérification.
- Ne jamais modifier la production sans GO explicite.
- Ne jamais accéder aux secrets.

## Workflows disponibles

### 1. Writing plans

Utiliser quand la tâche demande :
- une fonctionnalité nouvelle ;
- un refactor ;
- une migration ;
- une correction à risque.

Sortie attendue :
- objectif ;
- fichiers probablement concernés ;
- étapes ;
- tests ;
- risques ;
- point de validation humaine.

### 2. Executing plans

Utiliser quand un plan existe déjà.

Règles :
- suivre le plan ;
- ne pas élargir le périmètre ;
- signaler toute divergence ;
- afficher le diff ;
- lancer les tests.

### 3. Test-driven development

Utiliser quand une correction ou fonctionnalité peut être testée.

Cycle :
1. écrire ou adapter le test ;
2. constater l'échec si possible ;
3. corriger le code ;
4. relancer le test ;
5. vérifier le diff.

### 4. Systematic debugging

Utiliser quand il y a un bug ou une erreur.

Cycle :
1. reproduire ;
2. lire les logs ;
3. formuler une hypothèse ;
4. tester une seule hypothèse à la fois ;
5. corriger la cause racine ;
6. ajouter un test si possible.

### 5. Verification before completion

Avant de conclure :
- git status ;
- diff lu ;
- tests lancés ou raison claire si impossible ;
- aucun secret touché ;
- aucun fichier hors périmètre modifié ;
- résumé clair des changements.

### 6. Code review

Pour revue :
- vérifier lisibilité ;
- sécurité ;
- effets de bord ;
- tests ;
- cohérence avec règles projet ;
- dette technique créée ou réduite.

## Usage dans Aider

Charger ce fichier en lecture seule :

/read-only C:\AI_ControlTower\skills\superpowers\adapted-for-aider\superpowers_core_aider.md

Puis demander explicitement :

Applique le workflow Superpowers adapté : systematic debugging / TDD / executing plans / verification before completion.
