# Contrat d'interface

Toute modification passe par un accord écrit des deux membres.

| Rubrique | Valeur |
| --- | --- |
| Namespaces applicatifs | `zt-frontend`, `zt-api`, `zt-data`, `zt-attacker` |
| Namespaces outils | `kube-system`, `kyverno`, `falco`, `vault`, `external-secrets` |
| Étiquettes obligatoires | `app.kubernetes.io/name`, `app.kubernetes.io/component`, `app.kubernetes.io/part-of=zero-trust-k8s`, `zt/zone` |
| Frontal | nginx non privilégié, port 8080 |
| API | podinfo, port 9898 |
| Base de données | PostgreSQL, port 5432 |
| ServiceAccounts | `sa-<composant>` (ex. `sa-frontend`), `eso-vault` pour External Secrets |
| Ports d'outils | Vault 8200, Hubble Relay 4245, Falcosidekick 2801 |
| Nommage NetworkPolicy | `<action>-<source>-to-<destination>` |
| Nommage Kyverno | `<catégorie>-<règle>` (ex. `disallow-privileged`) |
| Chemins Vault | `secret/zt/<composant>/<nom>` |
| Règles de durcissement | non-root, système de fichiers en lecture seule, limites de ressources, pas de tag `latest` |
| Preuves | `docs/evidence/<phase>/<scénario>/` |
| Versions | voir `versions.md` |
