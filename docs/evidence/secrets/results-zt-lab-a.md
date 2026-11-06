# Mesure : secrets (Vault + ESO)
Date : 2026-11-07T00:12:39+02:00 | Machine : zt-lab-a | Noyau : 6.12.111+deb13-amd64

## État de la synchronisation
```
NAME                                    AGE   STATUS   CAPABILITIES   READY
secretstore.external-secrets.io/vault   12m   Valid    ReadWrite      True

NAME                                          STORETYPE     STORE   REFRESH INTERVAL   STATUS         READY   LAST SYNC
externalsecret.external-secrets.io/db-creds   SecretStore   vault   1m                 SecretSynced   True    4s
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
