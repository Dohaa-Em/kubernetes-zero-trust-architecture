# Threat Model

Status: final for phase 7 (7 November 2026). Every "measured" result below comes from a file
under `docs/evidence/`, and was obtained identically on both clusters (`zt-lab-a`, Debian 13,
and `zt-lab-b`, Ubuntu 24.04).

## 1. Scope and assets

| Asset | Why it matters | Where it lives |
|---|---|---|
| Database credentials (`db-creds`) | Full access to application data | Vault KV (source of truth), copied by ESO into a Kubernetes Secret |
| Application data (PostgreSQL) | Confidentiality and integrity of user data | PVC `db-data` on the node |
| Kubernetes API access (ServiceAccount tokens) | Read secrets, deploy workloads | Not mounted in application pods |
| Vault root token and unseal key | Unlock and administer every secret | `~/vault-init.json` on the admin machine, outside Git |
| Node / host filesystem | Container escape leads to full cluster compromise | k3s node, including the encryption key and the datastore |
| Kubernetes datastore and its backups | Contains every Secret | SQLite (`state.db`), Secrets encrypted at rest with AES-CBC |
| Security tooling (Kyverno, ESO, Vault, Falco, Cilium) | Compromising a control disables it or exposes what it protects | Dedicated namespaces with their own NetworkPolicy |
| Audit log and Falco alerts | Evidence of an attack | Node disk and Falcosidekick UI |

## 2. Trust boundaries

1. **Internet → frontend**: the only entry point of the application.
2. **frontend → API → database**: one namespace per tier, one allowed flow per hop.
3. **Workloads → Kubernetes API**: application pods have no token and no permission.
4. **Workloads → secrets tooling**: no workload talks to Vault; only the ESO controller does, with a dedicated identity.
5. **Containers → node kernel**: crossed only by Cilium and Falco (eBPF), which are privileged.

## 3. Adversary model

- **Primary:** an attacker with code execution inside the internet-facing frontend pod (initial foothold).
- **Secondary:** a stolen or leaked ServiceAccount token; an operator who deploys an unsafe workload by mistake or on purpose; a secret committed to Git; a stolen copy of the datastore or of a backup.
- **Out of scope:** node or kernel compromise, physical access, compromise of the container registries.

## 4. Attack scenarios, controls and measured effect

| ID | Scenario | MITRE ATT&CK | Baseline (measured) | Prevention | Detection | After all layers (measured, both clusters) |
|---|---|---|---|---|---|---|
| S1 | Compromised frontend moves laterally | T1046, T1059 | Reaches API, database, Kubernetes API and Internet | Default-deny NetworkPolicy enforced by Cilium, one flow per legitimate path | Falco `ZT Shell spawned in app container`; audit log records every `exec` with its command | **Only the API (9898)** is reachable; database, Kubernetes API and Internet blocked |
| S2 | Stolen ServiceAccount token | T1528, T1552.007 | `edit` role: reads secrets, creates pods (96 rules in `zt-data`) | No token mounted, zero RBAC permission; Vault role bound to `eso-vault` only | Falco `ZT Read of service account token` | No token in the pod, 23 default discovery rules, 7 dangerous permissions all `no`; a stolen `sa-frontend` token **cannot log into Vault** |
| S3 | Dangerous workload (privileged, hostPath, unlisted image) | T1610, T1611 | Accepted by the API server | Pod Security `restricted`; Kyverno: no `latest`, limits, image allowlist, **including initContainers** | Audit log records who created which pod, image and ServiceAccount | **Rejected** by both layers |
| S4 | Database password leak | T1552, T1552.007 | Readable by the frontend ServiceAccount, hand-made Secret, no history | Vault as source of truth, ESO with a namespaced store, Kyverno `secrets-only-from-eso` (create **and** update), RBAC, encryption at rest, Gitleaks on every commit | Vault audit device; Falco `ZT Interactive access to secrets tooling` and `ZT Read of Vault storage`; audit log at Metadata level | **Not readable**; rotation through Vault and ESO with a TCP check; 0 occurrence in Git; marker unreadable in the datastore after encryption |

Evidence: `docs/evidence/blast-radius.md`, `docs/evidence/integration/results-zt-lab-a.md` and
`results-zt-lab-b.md` (identical), plus one folder per layer under `docs/evidence/`.

## 5. Attacks on the security tooling itself

Every tool added to reduce a risk is also a new target. What we measured and changed:

| Target | Threat | Mitigation in place | Evidence |
|---|---|---|---|
| ESO controller | Its ClusterRole could read every Secret of the cluster | Scoped to `zt-data` (`scopedRBAC`, `scopedNamespace`): `kube-system`, `vault`, `zt-api` now `no` | `docs/evidence/secrets-policy/eso-scoped-rbac-zt-lab-a.txt`, `docs/evidence/review/retest-a1-a2-zt-lab-b.txt` |
| Vault | Reached by a compromised pod; root token leak | Default deny in `vault`, only ESO allowed on 8200; secrets never passed as `kubectl exec` arguments | `docs/evidence/network-vault-falco/` |
| Kyverno | Bypass of the rules; outage | initContainers validated (R1); updates validated (R10); fail-open and fail-closed behaviour measured | `docs/reviews/review-B-on-A.md`, `docs/evidence/fail-mode/` |
| Falco | Evasion of a rule | `docker-entrypoint` exclusion removed from the shell rule (A2): writing that string in a command silenced the alert, and container start launches no shell; the bypass now alerts, container start stays silent | `docs/evidence/detection/a2-docker-entrypoint-zt-lab-a.txt` |
| Falcosidekick UI | Default credentials | Login read from a Secret created outside Git | `docs/evidence/detection/ui-credentials-zt-lab-b.txt` |
| Security pods | Unneeded API tokens | Falco pods and every `default` ServiceAccount without token (kube-bench 5.1.5, 5.1.6) | `docs/evidence/kube-bench/README.md` |

## 6. Defence in depth by phase

1. **Cluster and CNI:** k3s without Flannel or Traefik, Cilium + Hubble; NetworkPolicy enforcement proved with a blocking test.
2. **Identity (RBAC):** one ServiceAccount per component, no token, zero permission for workloads.
3. **Network:** default deny ingress and egress in application and tooling namespaces, DNS only to CoreDNS, one explicit flow per legitimate path.
4. **Admission:** Pod Security `restricted` on application namespaces; Kyverno for tags, limits, image allowlist (containers and initContainers), safe defaults, generated default deny, and Secrets in `zt-data` written only by ESO.
5. **Secrets:** Vault (Raft, audit device, Kubernetes auth bound to one identity) as source of truth, ESO with a namespaced SecretStore, rotation with verification.
6. **Traceability and detection:** API audit log (Secrets at Metadata level only), Secret encryption at rest, Falco with five MITRE-tagged rules routed to Falcosidekick.
7. **Compliance:** kube-bench CIS k3s 1.9 (59 PASS, 4 FAIL analysed, same on both clusters); Kubescape NSA and MITRE (no failure left on `zt-*` namespaces).

## 7. Residual risks and known limits

| Area | Residual risk |
|---|---|
| Whole cluster | Single node: a node compromise defeats every control, including encryption at rest (key on the same node). |
| Application | The frontend can still call the API through the legitimate flow; L7 filtering is only demonstrated. The frontend is reachable only through `kubectl port-forward`, which NetworkPolicy does not filter. |
| Network | No pod-to-pod encryption; DNS to CoreDNS remains a possible exfiltration channel; the Falco pod may open HTTPS to any destination to download rules. |
| Admission | Pod Security and Kyverno cover `zt-*` namespaces only; ephemeral containers are not validated by the image rules; single Kyverno replica (fail-open on a clean stop); `kyverno.io/v1` policies are deprecated upstream. |
| Secrets | Vault without TLS inside the cluster, one unseal key, no auto-unseal: after a pod restart ESO stayed in error for about 160 minutes until a manual unseal (the application kept the last value). ESO can still write every Secret of `zt-data`. Running pods keep the old password until restarted. |
| Detection | Falco detects but does not block; the shell rule watches shell names only (`curl` or `nc` run directly are not caught); a stopped Falco is a silent blind spot. |
| Traceability | The audit log stays on the node and can be erased by a root attacker. |
| Interfaces | Hubble UI has no authentication; the Falcosidekick UI login overrides the chart default only through `envFrom` order. |
