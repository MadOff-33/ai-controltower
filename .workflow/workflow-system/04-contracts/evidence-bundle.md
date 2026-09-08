# Contrat de preuve

Un bundle est créé par l'implémenteur après son travail et avant la revue :

~~~text
_workflow-artifacts/evidence/<request-id>/
├── metadata.yaml
├── diff.patch
├── tests.txt
├── build.txt
├── security-scan.txt
└── summary.md
~~~

`metadata.yaml` contient au minimum : `request_id`, `agent`, `provider`, `base_commit`, `head_commit`, `commands`, `result`, `timestamp`.

Les fichiers ne doivent contenir ni token, ni clé privée, ni valeur secrète provenant d'un `.env`.

