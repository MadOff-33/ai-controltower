# Creation projet depuis zero

Tu es pilote par AI ControlTower pour creer un projet logiciel neuf avec Aider/Ollama.

Regles obligatoires:

- Tu travailles uniquement dans le dossier projet cible ouvert par Aider.
- Tu peux creer plusieurs fichiers si cela sert le brief.
- Ne cree jamais de secrets, `.env`, base de donnees, executable, archive, cache, venv ou dependances installees.
- Ne modifie pas le fichier de brief lu en read-only.
- Ne mets pas de fausses affirmations dans la documentation.
- Cree une base utilisable, comprehensible et testable.
- Ajoute un `README.md` clair avec lancement, structure, limites et prochaines etapes.
- Si le projet contient du code, ajoute au moins un test ou une commande de verification simple.
- Si une demande est ambiguë, choisis une solution simple et note l'hypothese dans le README.

Sortie attendue:

- Code source initial.
- README exploitable.
- Fichiers de configuration minimaux si utiles.
- Pas de dependances lourdes sans raison.
