#!/usr/bin/env bash
# Usage : scripts/measure.sh <étiquette>   (ex. baseline, phase-2)
set -u
LABEL="${1:?donner une étiquette}"
OUT="docs/evidence/${LABEL}/results-$(hostname).md"
mkdir -p "$(dirname "$OUT")"
SA="system:serviceaccount:zt-frontend:sa-frontend"
P=$(kubectl -n zt-frontend get pod -l app.kubernetes.io/component=frontend -o jsonpath='{.items[0].metadata.name}')

reach() {  # nom, commande exécutée depuis le pod frontal compromis
  if kubectl -n zt-frontend exec "$P" -- sh -c "$2" >/dev/null 2>&1; then echo "| $1 | ATTEIGNABLE |"; else echo "| $1 | bloqué |"; fi
}
yn() { kubectl auth can-i "$@" --as="$SA" 2>/dev/null || true; }

{
echo "# Mesure : ${LABEL}"
echo "Date : $(date -Is) | Machine : $(hostname) | Noyau : $(uname -r) | k3s : $(k3s --version | head -1)"
echo
echo "## S1 : depuis le pod frontal compromis"
echo "| Cible | Résultat |"; echo "| --- | --- |"
reach "API (zt-api:9898)"        "wget -q -T2 -O /dev/null http://api.zt-api.svc:9898/healthz"
reach "Base (zt-data:5432)"      "nc -z -w2 database.zt-data.svc 5432"
reach "Serveur API Kubernetes"   "nc -z -w2 kubernetes.default.svc 443"
reach "Internet (1.1.1.1:443)"   "nc -z -w3 1.1.1.1 443"
echo
echo "## S2 : droits du ServiceAccount sa-frontend"
echo "- Lire les Secrets de zt-data : $(yn get secrets -n zt-data)"
echo "- Lire les Secrets de zt-frontend : $(yn get secrets -n zt-frontend)"
echo "- Créer des pods dans zt-api : $(yn create pods -n zt-api)"
echo "- Exécuter dans un autre pod (zt-api) : $(yn create pods/exec -n zt-api)"
echo "- Nombre de règles autorisées dans zt-data : $(kubectl auth can-i --list --as="$SA" -n zt-data 2>/dev/null | tail -n +2 | wc -l)"
echo
echo "## S3 : un pod privilégié avec hostPath / est-il accepté ?"
if cat <<'POD' | kubectl apply --dry-run=server -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata: {name: s3-test, namespace: zt-attacker}
spec:
  containers:
  - name: c
    image: busybox:1.36
    securityContext: {privileged: true}
    volumeMounts: [{name: host, mountPath: /host}]
  volumes: [{name: host, hostPath: {path: /}}]
POD
then echo "- ACCEPTÉ (aucun contrôle d'admission)"; else echo "- REFUSÉ"; fi
echo
echo "## S4 : le mot de passe de la base est-il lisible par le pod compromis ?"
if kubectl -n zt-data get secret db-creds --as="$SA" >/dev/null 2>&1; then echo "- OUI, lisible par sa-frontend"; else echo "- non"; fi
} | tee "$OUT"
echo; echo "Résultats écrits dans $OUT"
