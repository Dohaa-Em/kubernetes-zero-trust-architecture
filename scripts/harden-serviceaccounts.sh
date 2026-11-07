#!/usr/bin/env bash
# scripts/harden-serviceaccounts.sh : durcissement relevé par kube-bench (CIS k3s 1.9)
# 5.1.5 : les ServiceAccounts "default" ne montent plus de token (aucun pod ne les utilise).
# 5.1.6 : les pods Falco n'ont pas besoin de l'API Kubernetes (métadonnées lues par le
#         socket containerd, plugin k8smeta désactivé) : pas de token pour eux.
# Les outils qui appellent l'API (ESO, Cilium, CoreDNS, metrics-server, local-path,
# Vault pour TokenReview) gardent leur token : exception justifiée dans le rapport.
set -euo pipefail

for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  [ "$ns" = "kube-system" ] && continue          # exclu par le contrôle CIS lui-même
  kubectl -n "$ns" patch serviceaccount default -p '{"automountServiceAccountToken": false}' >/dev/null
  echo "5.1.5  $ns/default : automountServiceAccountToken=false"
done

for sa in falco falco-falcosidekick falco-falcosidekick-ui; do
  kubectl -n falco patch serviceaccount "$sa" -p '{"automountServiceAccountToken": false}' >/dev/null
  echo "5.1.6  falco/$sa : automountServiceAccountToken=false"
done
# Les pods existants gardent leur token jusqu'au redémarrage
kubectl -n falco rollout restart ds/falco deploy/falco-falcosidekick deploy/falco-falcosidekick-ui
kubectl -n falco delete pod falco-falcosidekick-ui-redis-0

# 1.1.20 : certificats du plan de contrôle lisibles par root uniquement.
# Le * doit être développé par root (le dossier tls n'est pas lisible par l'utilisateur).
# A revérifier après une rotation des certificats k3s.
sudo sh -c 'chmod 600 /var/lib/rancher/k3s/server/tls/*.crt'
echo "1.1.20 certificats /var/lib/rancher/k3s/server/tls/*.crt : 600"
