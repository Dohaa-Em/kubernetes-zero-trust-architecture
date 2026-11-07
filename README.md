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
```bash
sudo cp cluster/k3s-config.yaml /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -
# install Cilium (see versions.md), then:
kubectl apply -f app/ -f rbac/ -f network/
# install Kyverno (see versions.md), then:
kubectl apply -f admission/
./scripts/measure.sh <label>
```
Tool versions are pinned in [`versions.md`](versions.md). The shared names used by all
components are defined in [`docs/01-interface-contract.md`](docs/01-interface-contract.md).

## Documentation
- [Threat model](docs/00-threat-model.md)
- [Test sheet](docs/02-test-sheet.md)

## Status
- Phases 0 to 4 done by Abir Majdi on zt-lab-a (threat model, baseline, RBAC, Pod Security, NetworkPolicy and Cilium, Kyverno).
- Phases 5 and 6 done by Doha El Merabet on zt-lab-b (Vault, External Secrets, API audit, etcd encryption, Falco).
- Integration (phase 7), in progress on zt-lab-a by Abir Majdi: API audit, etcd encryption, Vault and External Secrets replayed with evidence. Kyverno policy allowing Secrets in zt-data only from External Secrets Operator (admission/70). Falco with five MITRE-tagged rules replayed with evidence (docs/evidence/detection). Network policies for vault, external-secrets and falco applied (network/40, network/50). S1-S4 replayed on zt-lab-a with all layers active (docs/evidence/integration, blast-radius grid updated). Next: S1-S4 replay on zt-lab-b (Doha), kube-bench, limits and synthesis.
