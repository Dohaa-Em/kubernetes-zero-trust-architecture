#!/usr/bin/env bash
# secrets/vault-unseal.sh
# Initialise Vault (la première fois seulement) puis le descelle.
# A relancer après chaque redémarrage de la VM (Vault redevient scellé).
#
# Pourquoi passer par l'API HTTP (port-forward + curl) pour le descellement ?
# Tout argument d'un "kubectl exec" apparaît en clair dans l'URL de la requête,
# donc dans le journal d'audit Kubernetes (phase 6). La clé de descellement ne
# doit jamais passer en argument : on l'envoie dans le corps d'une requête HTTP.
set -euo pipefail

INIT="${VAULT_INIT_FILE:-$HOME/vault-init.json}"   # HORS du dépôt, droits 600
PORT=18200

kubectl -n vault wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 --timeout=600s

kubectl -n vault port-forward pod/vault-0 ${PORT}:8200 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
sleep 3
V="http://127.0.0.1:${PORT}/v1"

if [ "$(curl -s $V/sys/init | jq -r .initialized)" != "true" ]; then
  echo "== Initialisation de Vault (1 clé, seuil 1 : acceptable en lab uniquement)"
  umask 077
  curl -s -X PUT $V/sys/init -d '{"secret_shares":1,"secret_threshold":1}' > "$INIT"
  chmod 600 "$INIT"
  echo "Clés écrites dans $INIT (ne JAMAIS commit ce fichier)"
fi

if [ "$(curl -s $V/sys/seal-status | jq -r .sealed)" = "true" ]; then
  echo "== Descellement"
  # Le format de /sys/init (API) est "keys_base64" ; celui de la CLI est "unseal_keys_b64"
  jq '{key: (.keys_base64 // .unseal_keys_b64)[0]}' "$INIT" \
    | curl -s -X PUT $V/sys/unseal --data @- | jq '{sealed, progress}'
fi

curl -s $V/sys/seal-status | jq '{initialized, sealed, version, storage_type}'

# Après un redémarrage, ESO a échoué tant que Vault était scellé (SecretSyncedError,
# l'application garde la dernière valeur grâce à deletionPolicy: Retain).
# On relance la synchronisation sans attendre son délai de réessai.
if kubectl -n zt-data get externalsecret db-creds >/dev/null 2>&1; then
  kubectl -n zt-data annotate externalsecret db-creds force-sync="$(date +%s)" --overwrite >/dev/null
  echo "== Synchronisation ESO relancée"
fi
