# Hermes central guidance

- [validation_rule/creation_reliability] Un run Creation marque passed peut etre un faux positif si Aider cree des fichiers issus du texte de reponse ou du mojibake. Lesson: Refuser les sorties Creation contenant des noms de fichiers de type commande, arbre Markdown, commentaires dans le nom, ou mojibake dans les chemins/contenus avant de proposer le projet comme utilisable.
- [success/run_outcome] Run Creation valide par ControlTower.
- [experience/run_preparation] Run Creation prepare et valide structurellement, sans preuve de sortie modele. Lesson: Un dry-run valide la structure ControlTower, pas la qualite d'un audit Aider.
- [validation_rule/audit_report_reliability] Un audit couvert a 100 pourcent peut rester non fiable si les rapports sources ont un encodage suspect. Lesson: Distinguer couverture globale, qualite factuelle et proprete d encodage. Ne pas autoriser une correction automatique depuis un rapport consolide si les sources contiennent du mojibake.
- [experience/run_preparation] Run Audit prepare et valide structurellement, sans preuve de sortie modele. Lesson: Un dry-run valide la structure ControlTower, pas la qualite d'un audit Aider.
- [experience/run_preparation] Run Audit prepare et valide structurellement, sans preuve de sortie modele. Lesson: Un dry-run valide la structure ControlTower, pas la qualite d'un audit Aider.