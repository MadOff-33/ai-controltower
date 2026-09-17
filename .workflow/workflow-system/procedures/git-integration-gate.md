# Gate d'intégration Git

Codex effectue les contrôles finaux :

~~~bash
git status --short
git diff --check
git diff <base-sha>...<head-sha> --stat
git log --oneline <base-sha>..<head-sha>
~~~ 

Puis Codex vérifie les preuves et la décision Claude. Le merge, la PR ou le maintien de la branche est décidé explicitement par l'humain.
