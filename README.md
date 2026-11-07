# Kubernetes Zero Trust Architecture

A reproducible Zero Trust lab on Kubernetes: default-deny networking, least-privilege RBAC,
admission control, secret management and runtime detection, with measured results for four
attack scenarios.

## Architecture
```text
user -> frontend (zt-frontend:8080) -> api (zt-api:9898) -> database (zt-data:5432)
                                  attacker pod (zt-attacker) used to simulate an intruder
```
Stack: k3s, Cilium + Hubble, NetworkPolicy, RBAC, Pod Security Admission, Kyverno,
Vault + External Secrets Operator, Falco.

## Results (attacker inside the frontend pod)
See [`docs/evidence/blast-radius.md`](docs/evidence/blast-radius.md). Each phase closes more paths:

| Stage | Reaches database | Reads secrets | Creates privileged pod |
|---|---|---|---|
| Baseline | yes | yes | yes |
| RBAC | yes | no | yes |
| NetworkPolicy | no | no | yes |
| PSA + Kyverno | no | no | no |

## Reproduce

Run every command from the repository root. Versions are pinned in [`versions.md`](versions.md);
shared names are defined in [`docs/01-interface-contract.md`](docs/01-interface-contract.md).
Secrets, audit, encryption and detection steps (Vault, ESO, Falco) are detailed in
[`docs/reproduce-secrets-detection.md`](docs/reproduce-secrets-detection.md).

```bash
# 1. Audit and encryption drop-ins, BEFORE k3s (step 1 of docs/reproduce-secrets-detection.md)
sudo mkdir -p /etc/rancher/k3s/config.yaml.d /var/lib/rancher/k3s/server/logs
sudo cp cluster/audit/audit-policy.yaml /var/lib/rancher/k3s/server/audit-policy.yaml
sudo cp cluster/audit/k3s-audit.yaml /etc/rancher/k3s/config.yaml.d/20-audit.yaml
sudo cp cluster/audit/k3s-secrets-encryption.yaml /etc/rancher/k3s/config.yaml.d/30-secrets-encryption.yaml

# 2. k3s (pinned, without Flannel, kube-proxy network policy or Traefik)
sudo cp cluster/k3s-config.yaml /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.5+k3s1 sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. Cilium 1.20.4 (replaces kube-proxy, VXLAN tunnel, Hubble relay and UI)
cilium install --version 1.20.4 \
  --set cluster.name=default \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=127.0.0.1 --set k8sServicePort=6443 \
  --set routingMode=tunnel --set tunnelProtocol=vxlan \
  --set ipam.operator.clusterPoolIPv4PodCIDRList=10.42.0.0/16 \
  --set operator.replicas=1 \
  --set hubble.relay.enabled=true --set hubble.ui.enabled=true
cilium status --wait

# 4. Namespaces (with Pod Security "restricted" labels), application and RBAC
kubectl apply -f app/00-namespaces.yaml
kubectl apply -f app/ -f rbac/

# 5. Vault, External Secrets Operator and Falco: steps 2 to 4 of
#    docs/reproduce-secrets-detection.md

# 6. Network policies (Cilium, default deny)
kubectl apply -f network/

# 7. Kyverno chart 3.9.2 (PolicyException enabled), then the admission policies
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --version 3.9.2 \
  --set features.policyExceptions.enabled=true \
  --set features.policyExceptions.namespace=kyverno
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s
kubectl apply -f admission/
kyverno test admission/tests/

# 8. ServiceAccount hardening: LAST, after Kyverno (step 5 of docs/reproduce-secrets-detection.md)
./scripts/harden-serviceaccounts.sh

# 9. Measurements
./scripts/measure.sh <label>
```

## Documentation
- [Threat model](docs/00-threat-model.md)
- [Test sheet](docs/02-test-sheet.md)

## Status
- Phases 0 to 4 done by Abir Majdi on zt-lab-a (threat model, baseline, RBAC, Pod Security, NetworkPolicy and Cilium, Kyverno).
- Phases 5 and 6 done by Doha El Merabet on zt-lab-b (Vault, External Secrets, API audit, etcd encryption, Falco).
- Integration (phase 7) done on both clusters (tag `v0.9-integration`): API audit, Secret encryption at rest (SQLite datastore), Vault and External Secrets, Falco with five MITRE-tagged rules, and the Kyverno policy allowing Secrets in zt-data only from External Secrets Operator (admission/70). S1-S4 replayed with all layers active on zt-lab-a and zt-lab-b (docs/evidence/integration, blast-radius grid updated). kube-bench v0.16.0 (59 passed, 4 findings analysed) and Kubescape v4.0.20 (no failed control left on the zt-* namespaces) in docs/evidence/final. Cross-reviews found and fixed two real defects: initContainers bypassing three Kyverno policies (R1) and Secrets in zt-data still modifiable by the admin (R10). Fail-open and fail-closed behaviour of Kyverno measured (docs/evidence/fail-mode). Next: Trivy image scan and architecture diagrams (Doha), rebuild from scratch with the README alone (#24), final synthesis and report.
