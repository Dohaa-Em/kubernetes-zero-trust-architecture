#!/usr/bin/env bash
# Usage: scripts/measure.sh <label>   (ex: baseline, rbac, network, ...)
set -uo pipefail
LABEL="${1:?label requis}"
HOST="$(hostname)"
OUT="docs/evidence/${LABEL}/results-${HOST}.md"
mkdir -p "docs/evidence/${LABEL}"
SA="system:serviceaccount:zt-frontend:sa-frontend"

tcp() { # nom ns deploy host port
  if kubectl -n "$2" exec "deploy/$3" -- sh -c "nc -z -w 3 $4 $5" >/dev/null 2>&1
  then echo "| $1 | ATTEIGNABLE |"; else echo "| $1 | bloque |"; fi
}
can() { # description verbe ressource ns
  if [ "$(kubectl auth can-i "$2" "$3" -n "$4" --as="$SA" 2>/dev/null)" = "yes" ]
  then echo "| $1 | yes |"; else echo "| $1 | no |"; fi
}

{
echo "# Resultats ${LABEL} - ${HOST}"
echo
echo "- Date : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "- OS : $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "- k3s : $(k3s --version 2>/dev/null | head -1)"
echo "- Cilium : $(kubectl -n kube-system get ds cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | cut -d@ -f1)"
echo
echo "## S1 - Pod frontend compromis (depuis le pod frontend)"
echo "| Cible | Resultat |"; echo "|---|---|"
tcp "API (zt-api:9898)"            zt-frontend frontend api.zt-api.svc.cluster.local 9898
tcp "Base de donnees (zt-data:5432)" zt-frontend frontend database.zt-data.svc.cluster.local 5432
tcp "API Kubernetes (443)"         zt-frontend frontend kubernetes.default.svc.cluster.local 443
tcp "Internet (1.1.1.1:443)"       zt-frontend frontend 1.1.1.1 443
echo
echo "## S1b - Pod attaquant (zt-attacker)"
echo "| Cible | Resultat |"; echo "|---|---|"
if kubectl -n zt-attacker exec attacker -- curl -s -m 3 -o /dev/null http://api.zt-api.svc.cluster.local:9898 >/dev/null 2>&1
then echo "| API depuis l'attaquant | ATTEIGNABLE |"; else echo "| API depuis l'attaquant | bloque |"; fi
if kubectl -n zt-attacker exec attacker -- curl -s -m 3 -o /dev/null https://example.com >/dev/null 2>&1
then echo "| Internet depuis l'attaquant | ATTEIGNABLE |"; else echo "| Internet depuis l'attaquant | bloque |"; fi
echo
echo "## S2 - ServiceAccount sa-frontend vole"
echo "| Action | Resultat |"; echo "|---|---|"
can "lire les secrets de zt-data"      get    secrets     zt-data
can "lire les secrets de zt-api"       get    secrets     zt-api
can "creer des pods dans zt-data"      create pods        zt-data
can "supprimer des deployments zt-api" delete deployments zt-api
can "creer des roles dans zt-data"     create roles       zt-data
N=$(kubectl auth can-i --list -n zt-data --as="$SA" 2>/dev/null | tail -n +2 | wc -l)
echo "| nb de lignes de droits dans zt-data | $N |"
if kubectl -n zt-frontend exec deploy/frontend -- test -f /var/run/secrets/kubernetes.io/serviceaccount/token 2>/dev/null
then echo "| token monte dans le pod frontend | OUI |"; else echo "| token monte dans le pod frontend | non |"; fi
echo
echo "## S3 - Configuration dangereuse (dry-run serveur)"
R=$(cat <<'POD' | kubectl apply --dry-run=server -n zt-attacker -f - 2>&1
apiVersion: v1
kind: Pod
metadata: {name: evil-test}
spec:
  containers:
  - name: c
    image: alpine:3.20
    securityContext: {privileged: true}
    volumeMounts: [{name: h, mountPath: /host}]
  volumes: [{name: h, hostPath: {path: /}}]
POD
)
echo "| Pod privilegie + hostPath | $(echo "$R" | grep -q 'created (server dry run)' && echo ACCEPTE || echo REFUSE) |"
echo
echo "## S4 - Fuite du secret db-creds"
echo "| Test | Resultat |"; echo "|---|---|"
if kubectl -n zt-data get secret db-creds --as="$SA" >/dev/null 2>&1
then echo "| Lecture par sa-frontend | LISIBLE |"; else echo "| Lecture par sa-frontend | refusee |"; fi
} > "$OUT"
echo "Ecrit : $OUT"
