#!/usr/bin/env bash
# secrets/rotate-db-password.sh
# Démontre la rotation : nouveau mot de passe -> PostgreSQL + Vault -> ESO -> Secret k8s.
# Les preuves n'affichent JAMAIS le mot de passe, seulement son empreinte SHA-256.
# Usage : ./secrets/rotate-db-password.sh | tee docs/evidence/secrets/rotation-$(hostname).txt
set -euo pipefail

INIT="${VAULT_INIT_FILE:-$HOME/vault-init.json}"
ROOT_TOKEN=$(jq -r '.root_token' "$INIT")
vxin() { { printf '%s\n' "$ROOT_TOKEN"; cat; } | kubectl -n vault exec -i vault-0 -- \
           sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault "$@"' sh "$@"; }
k8s_hash() { kubectl -n zt-data get secret db-creds -o jsonpath='{.data.password}' | base64 -d | sha256sum | cut -c1-16; }

echo "Date : $(date -Is) | Machine : $(hostname)"
echo "Empreinte AVANT  (Secret k8s) : $(k8s_hash)"

NEWPW=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)
echo "Empreinte cible  (nouveau)    : $(printf '%s' "$NEWPW" | sha256sum | cut -c1-16)"

# 1. PostgreSQL d'abord (l'utilisateur est "appuser", cf. app/30-database.yaml).
#    Le SQL passe par stdin : pas de mot de passe dans les arguments de kubectl exec.
printf "ALTER USER appuser PASSWORD '%s';\n" "$NEWPW" \
  | kubectl -n zt-data exec -i deploy/database -- psql -q -U appuser -d appdb
echo "1. PostgreSQL : mot de passe changé"

# 2. Vault (nouvelle version KV)
printf '%s' "$NEWPW" | vxin kv put secret/zt/database/credentials password=- >/dev/null
echo "2. Vault : nouvelle version écrite"
unset NEWPW

# 3. ESO : on force une synchronisation immédiate (sinon attendre refreshInterval)
kubectl -n zt-data annotate externalsecret db-creds force-sync="$(date +%s)" --overwrite >/dev/null
sleep 10
kubectl -n zt-data get externalsecret db-creds
echo "Empreinte APRES  (Secret k8s) : $(k8s_hash)"

# 4. Preuve : la base accepte le mot de passe du Secret géré par ESO, en TCP
#    (127.0.0.1 -> règle "host ... scram-sha-256", donc le mot de passe est vérifié)
if kubectl -n zt-data get secret db-creds -o jsonpath='{.data.password}' | base64 -d \
   | kubectl -n zt-data exec -i deploy/database -- sh -c \
     'read -r PGPASSWORD; export PGPASSWORD; psql -h 127.0.0.1 -U appuser -d appdb -tAc "select 1"' \
   | grep -q 1; then
  echo "4. Connexion TCP avec le mot de passe venant de Vault/ESO : OK"
else
  echo "4. Connexion TCP : ECHEC (vérifier l'ordre PostgreSQL / Vault)"
fi
echo "Note : le pod garde l'ANCIEN mot de passe en variable d'environnement jusqu'à son"
echo "redémarrage ; le rechargement côté application est une piste d'amélioration."
