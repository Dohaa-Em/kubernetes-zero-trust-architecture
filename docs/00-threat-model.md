# Threat Model

## 1. Scope and assets
| Asset | Why it matters |
|---|---|
| Database credentials (`db-creds`) | Gives full access to application data |
| Kubernetes API access (ServiceAccount tokens) | Allows reading secrets and deploying workloads |
| Node / host filesystem | Container escape leads to full cluster compromise |
| Application data (PostgreSQL) | Confidentiality and integrity of user data |

## 2. Adversary model
- **Primary:** an attacker with code execution inside the internet-facing frontend pod (initial foothold).
- **Secondary:** a stolen or leaked ServiceAccount token; an operator who deploys an unsafe workload by mistake or on purpose; a secret committed to Git.
- **Out of scope:** node or kernel compromise, physical access, compromise of the container registries.

## 3. Attack scenarios, controls and measured effect
| ID | Scenario | MITRE ATT&CK | Baseline result | Controls | Result after controls |
|---|---|---|---|---|---|
| S1 | Compromised frontend pod moves laterally | T1046 Network Service Discovery | Reaches API, database, Kubernetes API and Internet | Cilium NetworkPolicy: default deny + explicit flows (phase 3) | Only the API (9898) is reachable |
| S2 | Stolen ServiceAccount token | T1528, T1552.007 | `edit` role: reads secrets, creates pods (96 rules in zt-data) | Least-privilege RBAC, token not mounted (phase 2) | No token in the pod, `can-i` = no, 23 default discovery rules |
| S3 | Dangerous workload (privileged, hostPath) | T1610, T1611 | Accepted by the API server | Pod Security Admission `restricted` + Kyverno policies (phase 4) | Rejected by both layers |
| S4 | Database password leak | T1552.007 | Readable by the frontend ServiceAccount | RBAC (phase 2); Vault + External Secrets (phase 5, in progress) | Not readable from the frontend |

Evidence: `docs/evidence/<phase>/results-<hostname>.md` and `docs/evidence/blast-radius.md`.

## 4. Defence in depth by phase
1. **Cluster and CNI:** k3s without Flannel/Traefik, Cilium + Hubble for flow visibility.
2. **Identity (RBAC):** one ServiceAccount per component, no automatic token, no secret access.
3. **Network:** default deny ingress and egress, DNS only to CoreDNS, one explicit flow per legitimate path.
4. **Admission:** Pod Security `restricted` on all application namespaces, Kyverno rules for image tags, resource limits and an image allowlist.
5. **Secrets:** Vault as source of truth, External Secrets Operator synchronisation (in progress).
6. **Detection:** Falco runtime rules, Kubernetes audit log, etcd secret encryption (in progress).

## 5. Residual risks and known limits
- The frontend can still call the API: a compromised frontend can abuse that legitimate path (no L7 filtering).
- Network policies are L3/L4 only; no FQDN or HTTP-level rules, no pod-to-pod encryption.
- The database password remains a Kubernetes Secret until the Vault integration is validated.
- Hubble UI and Vault run without TLS or authentication inside the lab cluster.
- Kyverno `ClusterPolicy` is deprecated upstream in favour of CEL-based policies.
- Single-node cluster: no high availability, a node compromise defeats all controls.
