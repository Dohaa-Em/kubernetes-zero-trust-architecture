# Mesure : secrets (Vault + ESO)
Date : 2026-11-06T19:39:17+01:00 | Machine : zt-lab-b | Noyau : 6.14.0-35-generic

## État de la synchronisation
```
NAME                                    AGE     STATUS   CAPABILITIES   READY
secretstore.external-secrets.io/vault   5m24s   Valid    ReadWrite      True

NAME                                          STORETYPE     STORE   REFRESH INTERVAL   STATUS         READY   LAST SYNC
externalsecret.external-secrets.io/db-creds   SecretStore   vault   1m                 SecretSynced   True    17s
```
- Secret db-creds possédé par : ExternalSecret/db-creds
- Mot de passe présent dans le dépôt Git : 0 occurrence(s)

## Qui peut lire secret/zt/database/credentials dans Vault ?
- Token Vault sans politique (default) : refusé
- Login rôle eso avec le SA eso-vault (zt-data) : AUTORISÉ
- Login rôle eso avec le SA volé sa-frontend : refusé
- Login rôle eso avec sa-attacker : refusé

## RBAC Kubernetes sur le Secret synchronisé
- get secret db-creds par zt-frontend:sa-frontend : no
- get secret db-creds par zt-api:sa-api : no
- get secret db-creds par zt-attacker:sa-attacker : no
- get secret db-creds par zt-data:sa-database : no
- get secret db-creds par zt-data:eso-vault : no
- get secrets zt-data par le contrôleur ESO : yes
