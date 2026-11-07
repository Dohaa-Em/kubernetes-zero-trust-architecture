#!/usr/bin/env bash
# secrets/rotate-db-password.sh
# Rotation : nouveau mot de passe -> PostgreSQL + Vault -> ESO -> Secret k8s -> test TCP.
# Les preuves n'affichent JAMAIS le mot de passe, seulement son empreinte SHA-256.
# Sort en erreur (code 1) si la synchronisation ou le test final échoue.
# Usage : ./secrets/rotate-db-password.sh | tee docs/evidence/secrets/rotation-$(hostname).txt
set -euo pipefail

INIT="${VAULT_INIT_FILE:-$HOME/vault-init.json}"
TIMEOUT="${SYNC_TIMEOUT:-90}"
ROOT_TOKEN=$(jq -r '.root_token' "$INIT")
vxin() { { printf '%s\n' "$ROOT_TOKEN"; cat; } | kubectl -n vault exec -i vault-0 -- \
           sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault "$@"' sh "$@"; }
k8s_hash() { kubectl -n zt-data get secret db-creds -o jsonpath='{.data.password}' | base64 -d | sha256sum | cut -c1-16; }
fail() { echo "ECHEC : $*" >&2; exit 1; }

echo "Date : $(date -Is) | Machine : $(hostname)"
echo "Empreinte AVANT  (Secret k8s) : $(k8s_hash)"

NEWPW=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)
TARGET=$(printf '%s' "$NEWPW" | sha256sum | cut -c1-16)
echo "Empreinte cible  (nouveau)    : $TARGET"

# 1. PostgreSQL d'abord (utilisateur appuser, cf. app/30-database.yaml).
#    Le SQL passe par stdin : pas de mot de passe dans les arguments de kubectl exec.
printf "ALTER USER appuser PASSWORD '%s';\n" "$NEWPW" \
  | kubectl -n zt-data exec -i deploy/database -- psql -q -v ON_ERROR_STOP=1 -U appuser -d appdb \
  || fail "changement du mot de passe dans PostgreSQL"
echo "1. PostgreSQL : mot de passe changé"

# 2. Vault (nouvelle version KV)
printf '%s' "$NEWPW" | vxin kv put secret/zt/database/credentials password=- >/dev/null \
  || fail "écriture dans Vault"
echo "2. Vault : nouvelle version écrite"
unset NEWPW

# 3. ESO : synchronisation forcée, puis attente du NOUVEAU mot de passe dans le Secret
kubectl -n zt-data annotate externalsecret db-creds force-sync="$(date +%s)" --overwrite >/dev/null
for ((i = 0; i < TIMEOUT; i += 3)); do
  [ "$(k8s_hash)" = "$TARGET" ] && break
  sleep 3
done
[ "$(k8s_hash)" = "$TARGET" ] || fail "le Secret n'a pas reçu le nouveau mot de passe en ${TIMEOUT}s"
kubectl -n zt-data wait --for=condition=Ready externalsecret/db-creds --timeout=30s >/dev/null \
  || fail "ExternalSecret db-creds pas Ready"
kubectl -n zt-data get externalsecret db-creds
echo "3. ESO : Secret synchronisé en ${i}s"
echo "Empreinte APRES  (Secret k8s) : $(k8s_hash)"

# 4. Preuve : la base accepte le mot de passe du Secret géré par ESO, en TCP
#    (127.0.0.1 -> règle "host ... scram-sha-256", donc le mot de passe est vérifié)
kubectl -n zt-data get secret db-creds -o jsonpath='{.data.password}' | base64 -d \
  | kubectl -n zt-data exec -i deploy/database -- sh -c \
    'read -r PGPASSWORD || true; export PGPASSWORD; psql -h 127.0.0.1 -U appuser -d appdb -tAc "select 1"' \
  | grep -qx 1 || fail "connexion TCP avec le mot de passe venant de Vault/ESO"
echo "4. Connexion TCP avec le mot de passe venant de Vault/ESO : OK"
echo "Note : le pod garde l'ANCIEN mot de passe en variable d'environnement jusqu'à son"
echo "redémarrage ; le rechargement côté application est une piste d'amélioration."
