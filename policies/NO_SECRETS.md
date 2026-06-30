# NO SECRETS

Règle absolue : aucun secret dans le contexte LLM.

Ne jamais ajouter à Aider, ChatGPT ou tout agent :
- .env
- clés API
- tokens GitHub
- clés SSH
- credentials WooCommerce
- credentials Stripe
- credentials Google
- fichiers de sauvegarde contenant des identifiants

Si un fichier contient un secret, il doit être exclu du contexte.
