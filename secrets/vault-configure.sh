#!/usr/bin/env bash
# secrets/vault-configure.sh
# Configure Vault après init + unseal : audit, KV v2, politique, auth Kubernetes,
# et copie du mot de passe PostgreSQL ACTUEL dans Vault.
# A lancer depuis la racine du dépôt :  ./secrets/vault-configure.sh
#
# Le token root et le mot de passe passent par l'entrée standard (stdin), jamais
# en argument de "kubectl exec" (sinon ils seraient visibles dans l'audit k8s).
set -euo pipefail

INIT="${VAULT_INIT_FILE:-$HOME/vault-init.json}"
ROOT_TOKEN=$(jq -r '.root_token' "$INIT")

# vx  : exécute "vault <args>" dans le pod, token lu sur la 1re ligne de stdin
# vxin: idem, et le reste de stdin est transmis à vault (politique, mot de passe)
vx()   { printf '%s\n' "$ROOT_TOKEN" | kubectl -n vault exec -i vault-0 -- \
           sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault "$@"' sh "$@"; }
vxin() { { printf '%s\n' "$ROOT_TOKEN"; cat; } | kubectl -n vault exec -i vault-0 -- \
           sh -c 'read -r VAULT_TOKEN; export VAULT_TOKEN; exec vault "$@"' sh "$@"; }

echo "== 1. Journal d'audit Vault (volume /vault/audit)"
vx audit list 2>/dev/null | grep -q '^file/' || vx audit enable file file_path=/vault/audit/vault-audit.log

echo "== 2. Moteur KV v2 sur secret/"
vx secrets list | grep -q '^secret/' || vx secrets enable -path=secret kv-v2

echo "== 3. Mot de passe ACTUEL de PostgreSQL -> Vault (valeur jamais affichée)"
# PostgreSQL a été initialisé avec ce mot de passe : on le reprend tel quel.
kubectl -n zt-data get secret db-creds -o jsonpath='{.data.password}' | base64 -d \
  | vxin kv put secret/zt/database/credentials password=-

echo "== 4. Politique de moindre privilège : lecture seule d'UN chemin"
vxin policy write zt-database-read - <<'EOF'
# Lecture seule du mot de passe de la base, rien d'autre.
path "secret/data/zt/database/*" {
  capabilities = ["read"]
}
EOF

echo "== 5. Authentification Kubernetes"
vx auth list | grep -q '^kubernetes/' || vx auth enable kubernetes
# Vault tourne dans le cluster : il utilise son propre token et la CA du pod
# pour appeler TokenReview (ClusterRoleBinding auth-delegator créé par le chart).
vx write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"

# Rôle lié à UN ServiceAccount dans UN namespace, audience "vault", TTL court.
vx write auth/kubernetes/role/eso \
  bound_service_account_names=eso-vault \
  bound_service_account_namespaces=zt-data \
  audience=vault \
  token_policies=zt-database-read \
  token_ttl=15m token_max_ttl=30m

echo "== Vérification"
vx kv metadata get secret/zt/database/credentials
vx read auth/kubernetes/role/eso
