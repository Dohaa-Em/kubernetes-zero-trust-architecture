#!/usr/bin/env bash
# secrets/verify-secrets.sh : preuves de la phase 5 (scénario S4)
# Usage : ./secrets/verify-secrets.sh | tee docs/evidence/secrets/results-$(hostname).md
set -uo pipefail

INIT="${VAULT_INIT_FILE:-$HOME/vault-init.json}"
ROOT_TOKEN=$(jq -r '.root_token' "$INIT")
vxtok() { local t="$1"; shift; { printf '%s\n' "$t"; cat; } | kubectl -n vault exec -i vault-0 -- \
           sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault "$@"' sh "$@"; }
ok() { if "$@" >/dev/null 2>&1; then echo "AUTORISÉ"; else echo "refusé"; fi; }

echo "# Mesure : secrets (Vault + ESO)"
echo "Date : $(date -Is) | Machine : $(hostname) | Noyau : $(uname -r)"
echo
echo "## État de la synchronisation"
echo '```'
kubectl -n zt-data get secretstore,externalsecret
echo '```'
echo "- Secret db-creds possédé par : $(kubectl -n zt-data get secret db-creds \
  -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')"
echo "- Mot de passe présent dans le dépôt Git : $(git grep -nIi 'POSTGRES_PASSWORD.*value:' -- . ':!docs' ':!secrets/verify-secrets.sh' | wc -l) occurrence(s)"
echo
echo "## Qui peut lire secret/zt/database/credentials dans Vault ?"
DEF=$(vxtok "$ROOT_TOKEN" token create -policy=default -ttl=5m -field=token </dev/null)
echo "- Token Vault sans politique (default) : $(ok vxtok "$DEF" kv get secret/zt/database/credentials </dev/null)"

ESO_JWT=$(kubectl -n zt-data create token eso-vault --audience vault --duration 10m)
echo "- Login rôle eso avec le SA eso-vault (zt-data) : $(printf '%s' "$ESO_JWT" | ok vxtok "$DEF" write auth/kubernetes/login role=eso jwt=-)"

FE_JWT=$(kubectl -n zt-frontend create token sa-frontend --audience vault --duration 10m)
echo "- Login rôle eso avec le SA volé sa-frontend : $(printf '%s' "$FE_JWT" | ok vxtok "$DEF" write auth/kubernetes/login role=eso jwt=-)"

ATT_JWT=$(kubectl -n zt-attacker create token sa-attacker --audience vault --duration 10m)
echo "- Login rôle eso avec sa-attacker : $(printf '%s' "$ATT_JWT" | ok vxtok "$DEF" write auth/kubernetes/login role=eso jwt=-)"
echo
echo "## RBAC Kubernetes sur le Secret synchronisé"
for sa in zt-frontend:sa-frontend zt-api:sa-api zt-attacker:sa-attacker zt-data:sa-database zt-data:eso-vault; do
  echo "- get secret db-creds par $sa : $(kubectl auth can-i get secret/db-creds -n zt-data --as=system:serviceaccount:$sa)"
done
echo "- get secrets zt-data par le contrôleur ESO : $(kubectl auth can-i get secrets -n zt-data \
  --as=system:serviceaccount:external-secrets:external-secrets)"
