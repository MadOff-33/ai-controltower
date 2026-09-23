# Contrat de revue indépendante

~~~yaml
request_id: ""
base_commit: ""
head_commit: ""
reviewer: "Claude"
decision: "APPROVED|CHANGES_REQUIRED"
findings:
  - id: "F-001"
    severity: "blocker|high|medium|low"
    file: ""
    line: null
    observation: ""
    recommendation: ""
    verified: false
scope_checked: []
tests_reproduced: []
~~~

La revue est indépendante : le reviewer ne modifie pas la branche d'implémentation. Un `CHANGES_REQUIRED` revient à Codex pour une nouvelle boucle de correction et de preuve.

