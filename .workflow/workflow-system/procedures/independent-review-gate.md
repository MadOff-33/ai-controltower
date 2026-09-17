# Gate de revue indépendante

Le gate est franchi seulement si :

- le diff correspond à la spec ;
- les tests ciblés et la suite prévue ont été exécutés ;
- le bundle de preuves est complet ;
- aucun secret n'est exposé ;
- Claude a rendu APPROVED ;
- aucune correction n'a été faite après cette approbation.

Si un point échoue, retourner à l'étape concernée. Une nouvelle modification invalide l'approbation précédente.
