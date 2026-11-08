# Zero Trust for Kubernetes Workloads: Design, Implementation and Measured Results

**Mini-project 1: Securing Kubernetes workloads with a Zero Trust approach**

| | |
| --- | --- |
| Authors | Abir Majdi (A), Doha El Merabet (B) |
| Repository | `penelopeeckhar/kubernetes-zero-trust-architecture` |
| Clusters | `zt-lab-a` (Debian 13), `zt-lab-b` (Ubuntu 24.04), k3s v1.36.5+k3s1, single node |
| Writing | B (this document), review by A |
| Status | Updated 8 November 2026. Complete: cross-review (A and B), demo video, tag `v1.0.0`. |
| Demo video | https://... |

---

## 1. Context and objective

An organisation runs several applications on a shared Kubernetes cluster. Network
traffic is too permissive, some workloads hold excessive privileges and configurations
are not checked before they reach the cluster. The goal is a Zero Trust architecture:
no communication and no access is trusted by default, every one is allowed explicitly.

Central question of the subject:

> How can the Zero Trust principle be applied to Kubernetes workloads without
> multiplying security mechanisms unnecessarily?

Our method answers it with measurements rather than opinions. We first deploy the
application **without protection** (baseline), replay four attack scenarios, then add one
layer at a time and replay the same scenarios after each layer. A tool is kept only if it
reduces a measured risk that the previous layers do not already cover (section 10).

## 2. Architecture

### 2.1 Namespaces and components

| Namespace | Component | Image | Port | ServiceAccount |
| --- | --- | --- | --- | --- |
| `zt-frontend` | Frontend (reverse proxy) | `nginxinc/nginx-unprivileged:1.27-alpine` | 8080 | `sa-frontend` |
| `zt-api` | API | `ghcr.io/stefanprodan/podinfo:6.7.1` | 9898 | `sa-api` |
| `zt-data` | Database | `postgres:16-alpine` (PVC 1 Gi) | 5432 | `sa-database` |
| `zt-data` | Secret synchronisation identity | (no pod) | | `eso-vault` |
| `zt-attacker` | Simulated internal attacker | `curlimages/curl:8.10.1` | | `sa-attacker` |
| `vault` | HashiCorp Vault 2.0.4, Raft storage | `hashicorp/vault` | 8200 | `vault` |
| `external-secrets` | External Secrets Operator 2.14.0 | | | `external-secrets` |
| `falco` | Falco 0.45.2, Falcosidekick 2.35.1 + UI | | 2801, 2802 | `falco` |
| `kyverno` | Kyverno v1.19.2 | | | |
| `kube-system` | Cilium 1.20.4, Hubble, CoreDNS | | | |

Names, labels and ports are fixed in `docs/01-interface-contract.md`.

### 2.2 Trust boundaries

1. **Internet → frontend**: the only entry point of the application.
2. **Frontend → API → database**: each tier lives in its own namespace and talks only to the next one.
3. **Workloads → Kubernetes API**: application pods do not need the API at all, so they get no token.
4. **Application → secrets tooling**: workloads never talk to Vault. Only the ESO controller does, with a dedicated identity.
5. **Containers → node kernel**: crossed only by Cilium and Falco (eBPF), which are therefore privileged components to protect.

The three architecture diagrams (before/after, allowed flows, Vault/ESO sequence) are in `docs/architecture/README.md`.

### 2.3 Flows

| Flow | Allowed | Control |
| --- | --- | --- |
| frontend → api:9898 | yes | NetworkPolicy `allow-frontend-to-api` |
| api → database:5432 | yes | NetworkPolicy `allow-api-to-database` |
| all pods → CoreDNS:53 | yes | `allow-dns-egress` |
| frontend → database, frontend → Kubernetes API, any pod → Internet | **no** | default deny ingress and egress |
| ESO → Vault:8200, Vault → kube-apiserver (TokenReview) | yes | `docs/flows-vault-eso.md` |
| Falco → Falcosidekick:2801 → UI:2802 → Redis:6379 | yes | `docs/flows-falco.md` |

Diagrams of the architecture before and after, of every allowed flow (and the tested refused ones) and of the Vault → ESO → database sequence: `docs/architecture/README.md`.

## 3. Threat model

Full model: `docs/00-threat-model.md`. The adversary has code execution inside the
internet-facing frontend pod. Four scenarios are replayed at every phase:

| ID | Scenario | MITRE ATT&CK |
| --- | --- | --- |
| S1 | Compromised frontend moves laterally | T1046, T1059 |
| S2 | Stolen ServiceAccount token | T1528, T1552.007 |
| S3 | Dangerous workload (privileged, hostPath) | T1610, T1611 |
| S4 | Database password leak | T1552 |

## 4. Implementation by phase

Each subsection follows the same structure: what was done, proof, limit.

### 4.1 Cluster and CNI (A and B)

k3s is installed without Flannel, Traefik or its embedded NetworkPolicy controller, so
that Cilium is the only CNI and the only policy engine. Both clusters use the same pinned
versions (`versions.md`) and produced **identical baseline results**
(`docs/evidence/baseline/results-zt-lab-a.md` and `results-zt-lab-b.md`): from the
frontend, the API, the database, the Kubernetes API and the Internet are all reachable,
`sa-frontend` holds the `edit` role (96 rules in `zt-data`), a privileged pod with
`hostPath: /` is accepted and the database password is readable.

The requirement to prove that the CNI enforces NetworkPolicy is met by a dedicated
test: a deny-egress policy on `zt-attacker` turns a successful request into a timeout,
and Hubble shows the `Policy denied DROPPED` verdict
(`docs/evidence/phase-1/networkpolicy-check/`).

### 4.2 RBAC and identities (A)

**ServiceAccounts and permissions.** The repository grants no Role or RoleBinding to the application accounts. Least privilege here means zero Kubernetes permissions, because no component of the application talks to the Kubernetes API.

| ServiceAccount | Component | Kubernetes permissions | Token mounted | Reason |
| --- | --- | --- | --- | --- |
| `sa-frontend` (`zt-frontend`) | Frontend (nginx) | none | no | Serves HTTP and calls the API over the network only |
| `sa-api` (`zt-api`) | API | none | no | Reaches the database over the network only |
| `sa-database` (`zt-data`) | Database | none | no | PostgreSQL needs no cluster access |
| `sa-attacker` (`zt-attacker`) | Simulation of a compromised pod | none | no | Any right would invalidate scenarios S1 to S4 |
| `eso-vault` (`zt-data`) | Used by the External Secrets Operator to authenticate to Vault | none | no | ESO requests a short-lived token for it (TokenRequest); the account holds no right itself |

**Dangerous permissions checked** (`docs/evidence/rbac/dangerous-permissions-zt-lab-a.txt`, `kubectl auth can-i --as=...` for the five accounts): read Secrets in all namespaces, create pods, `pods/exec`, create RoleBindings, `escalate` and `bind` on ClusterRoles, `impersonate` users and any verb on any resource (`* *`). Every answer is `no`.

Measured effect (`docs/evidence/rbac/`): the baseline `edit` binding is removed, tokens
are no longer mounted (`automountServiceAccountToken: false` on every ServiceAccount
and pod), and the rules available to `sa-frontend` in `zt-data` drop from **96 to 23**
(default discovery rules only). Reading secrets, creating pods and `pods/exec` are all
denied. S2 and S4 are closed at the Kubernetes API level.

### 4.3 Network: NetworkPolicy and Cilium (A)

**Flow matrix.**

| Flow | Policy | Result | Proof |
| --- | --- | --- | --- |
| frontend → API, TCP 9898 | `allow-frontend-to-api-egress` and `-ingress` | allowed | Hubble `FORWARDED` |
| API → database, TCP 5432 | `allow-api-to-database-egress` and `-ingress` | allowed | `nc` from the API pod succeeds, the same test from the frontend times out; Hubble `FORWARDED` (`docs/evidence/network/api-to-database-zt-lab-a.txt`) |
| application pods → CoreDNS, port 53 | `allow-dns-egress` | allowed | policy in `network/00-default-deny-and-dns.yaml` |
| frontend → database | none (default deny) | **blocked** | Hubble `EGRESS DENIED`, `DROPPED` |
| frontend → Kubernetes API (node `10.0.2.15:6443`) | none (default deny) | **blocked** | Hubble `EGRESS DENIED`, `DROPPED` |
| frontend → Internet (`1.1.1.1:443`) | none (default deny) | **blocked** | Hubble `EGRESS DENIED`, `DROPPED` |
| External Secrets Operator → Vault, TCP 8200 | `network/40-vault-eso.yaml` | allowed | ExternalSecret stays `SecretSynced` |
| attacker pod → Vault, TCP 8200 | none (default deny) | **blocked** | request times out (`http=000`, exit code 28) |
| Falco → Falcosidekick | `network/50-falco.yaml` | allowed | a new alert reaches the UI (`WebUI - POST OK (200)`) |
| Falco → Internet, TCP 443 | `network/50-falco.yaml` | allowed (limit) | rules download by `falcoctl`; any destination is allowed |

Proofs for the last four rows: `docs/evidence/network-vault-falco/` (both clusters).

Hubble captures from the compromised frontend (abridged excerpt: identities and retransmissions removed; full capture in `docs/evidence/network/hubble-frontend-flows-zt-lab-a.txt`):

```
Nov  7 18:54:00.540: zt-frontend/frontend-5d9d6df54-tkphc:38409 <> zt-data/database-55f4778c8d-wwt6l:5432 policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Nov  7 18:54:00.540: zt-frontend/frontend-5d9d6df54-tkphc:38409 <> zt-data/database-55f4778c8d-wwt6l:5432 Policy denied DROPPED (TCP Flags: SYN)
Nov  7 18:54:03.342: zt-frontend/frontend-5d9d6df54-tkphc:36489 <> 10.0.2.15:6443 (host) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Nov  7 18:54:03.342: zt-frontend/frontend-5d9d6df54-tkphc:36489 <> 10.0.2.15:6443 (host) Policy denied DROPPED (TCP Flags: SYN)
Nov  7 18:54:06.236: zt-frontend/frontend-5d9d6df54-tkphc:38193 <> 1.1.1.1:443 (world) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
Nov  7 18:54:06.236: zt-frontend/frontend-5d9d6df54-tkphc:38193 <> 1.1.1.1:443 (world) Policy denied DROPPED (TCP Flags: SYN)
```

Default deny ingress and egress in every application namespace, explicit DNS, then one
policy per legitimate flow. After this phase the frontend still reaches the API (a
legitimate flow) but no longer the database, the Kubernetes API or the Internet
(`docs/evidence/network/`). A CiliumNetworkPolicy demonstrates L7 filtering
(`GET /healthz` forwarded, `GET /version` denied). It is kept as a demonstration only, to
avoid tying every flow to Cilium (`docs/architecture-networkpolicy-vs-cilium.md`).

**Limits.** No policy allows ingress to the frontend: it is reachable only through `kubectl port-forward`, which goes through the kubelet and is not filtered by NetworkPolicy, so the "Internet → frontend" boundary is not really exercised (R4). The DNS egress rule lets a pod query CoreDNS for any name, and CoreDNS also resolves external names: DNS tunnelling remains a possible exfiltration channel (R6). A Cilium DNS rule limited to `*.cluster.local` would reduce it.

### 4.4 Admission: Pod Security Admission and Kyverno (A)

**Failure modes.** All Kyverno webhooks use `failurePolicy: Fail`, and the lab runs a single admission-controller replica. We measured two opposite behaviours (`docs/evidence/fail-mode/analysis.md`). When the controller is stopped cleanly (`scale --replicas=0`), Kyverno removes its resource webhooks (10 webhook configurations drop to 2) and a pod using the `latest` tag is admitted: the cluster is fail-open. When the controller crashes (pod killed with `--force --grace-period=0`), the webhooks stay registered, so the API server applies `Fail`: every pod creation, legitimate or not, is refused for about 30 seconds until the new pod is ready: the cluster is fail-closed. After a clean restart, protection came back 9 seconds after the rollout finished. A single replica therefore means that a clean stop removes the controls and a crash briefly blocks new pods. Three replicas with a PodDisruptionBudget are the usual mitigation; this was not tested on the single-node VM.

**Rules.**

| Policy | Type | Mode | Effect |
| --- | --- | --- | --- |
| `best-practices-disallow-latest-tag` | validate | Enforce | Refuses images without a tag or with `latest`, in containers and initContainers |
| `best-practices-require-limits` | validate | Enforce | Requires CPU and memory limits on containers and initContainers |
| `supply-chain-restrict-images` | validate | Enforce | Image allowlist: `ghcr.io/stefanprodan/*`, `nginxinc/nginx-unprivileged`, `postgres`, `curlimages/curl`, for containers and initContainers |
| `defaults-mutate-pod-defaults` | mutate | n/a | Adds secure defaults to pods |
| `defaults-generate-default-deny` | generate | n/a | Creates a default-deny NetworkPolicy in every new `zt-*` namespace |
| `secrets-only-from-eso` | validate | Enforce | Only the External Secrets Operator ServiceAccount may create or update Secrets in `zt-data`; `allowExistingViolations: false`, so an existing Secret cannot be edited by anyone else either |

The policies apply to the `zt-*` namespaces only (evidence: `docs/evidence/admission-kyverno/`, `docs/evidence/kyverno-extra/`, `docs/evidence/secrets-policy/`).

**Gaps found by cross-review.** The review by Doha El Merabet found two real holes in our own policies. Both were fixed and retested on both clusters. initContainers escaped the tag, limits and allowlist rules (R1, commit `8441fdf`, `docs/evidence/review/`). A Secret in `zt-data` could still be modified by the administrator, because Kyverno tolerates existing violations unless a rule sets `allowExistingViolations: false` ([Kyverno documentation](https://kyverno.io/docs/policy-types/cluster-policy/validate/)); that setting closes it (R10, commit `8ca98b2`, `docs/evidence/secrets-policy/r10-fix-zt-lab-a.txt`). Finding such holes by review is an argument for the method.

**Limits that remain.** Ephemeral containers (`kubectl debug`) go through a subresource that the Pod CREATE rules do not match, so the image rules do not validate them. The mutation `+(automountServiceAccountToken): false` only applies when the field is absent: a pod that sets it to `true` keeps its token (seen with `detection/tests/token-reader-pod.yaml`), so it is a safe default and not a control (R8). The ClusterRole given to Kyverno's background controller to generate the default deny can also delete NetworkPolicies in the whole cluster: compromising Kyverno would erase the default deny (R9).

**Rollout.** The policies were written and tested on a lab with no existing workload, so they went to `Enforce` directly (commit `961d229`, 3 November). We did not run an `Audit` phase. On a production cluster the usual path is `Audit`, review of the policy reports, then `Enforce`, so that existing workloads are not blocked.

All application namespaces enforce Pod Security `restricted`, which rejects the S3
privileged/hostPath pod even before Kyverno is involved. Kyverno adds what PSA cannot
express: no `latest` tag, mandatory resource limits, an image allowlist, mutation of
secure defaults, and generation of a default-deny NetworkPolicy for every new `zt-*`
namespace (with the ClusterRole that Kyverno's background controller needs for it). A documented PolicyException (`admission/60-policy-exception.yaml`) allows the `latest` tag only for
test pods named `latest-exception-*` in `zt-attacker`, for the policy `best-practices-disallow-latest-tag`; its evidence is in `docs/evidence/kyverno-extra/`.

### 4.5 Secrets: Vault and External Secrets Operator (B)

**Problem.** In the baseline the database password is a Kubernetes Secret created by
hand. It is base64, not encrypted. Any identity with `get secrets` can read it, it has no
history and nothing rotates it. RBAC (4.2) already stops the frontend from reading it,
but the secret still has no owner and no lifecycle.

**Design.** Vault becomes the single source of truth. The External Secrets Operator
copies the value into a Kubernetes Secret that the database consumes unchanged.

```text
Vault (KV v2, secret/zt/database/credentials)
   ▲  Kubernetes auth, role "eso", short-lived token
   │
ESO controller ──(TokenRequest for SA eso-vault, audience "vault")──► kube-apiserver
   │
   ▼  creates and owns
Secret zt-data/db-creds ──env──► PostgreSQL pod
```

| Decision | Choice | Reason |
| --- | --- | --- |
| Vault storage | Integrated Raft, 1 replica, **no dev mode** | Realistic: data persists, Vault starts sealed |
| Unseal | 1 key, threshold 1, kept in `~/vault-init.json` (mode 600, outside the repository, blocked by `.gitignore`) | Acceptable for a lab only (see limits) |
| Audit | Vault file audit device on its own volume | Every secret read is traceable |
| Engine | KV v2 | Versioned secrets: rotation history is visible |
| Policy `zt-database-read` | `read` on `secret/data/zt/database/*` only | Least privilege per path |
| Auth role `eso` | bound to SA `eso-vault`, namespace `zt-data`, audience `vault`, TTL 15 min | A token from any other identity is useless |
| Store | `SecretStore` in `zt-data`, not `ClusterSecretStore` | A cluster-wide store could be referenced from any namespace, which widens the blast radius |
| Target | `creationPolicy: Owner`, `deletionPolicy: Retain`, refresh 1 min | Ownership is provable, and a Vault outage does not delete the last good value |
| Injection | ESO rather than the Vault Agent sidecar | Application unchanged, and **no flow from workloads to Vault** |

**Handling secrets in commands.** Kubernetes audit logging (4.6) records the full URL of
every `kubectl exec`, including its arguments. A command such as
`kubectl exec vault-0 -- vault login <token>` would therefore copy the root token into
the audit log. All scripts in `secrets/` pass the token, the unseal key and the
passwords through standard input or the Vault HTTP API, never as arguments. The proof
is visible in Falco: the alert for an administrative command shows
`cmd=sh -c read -r VAULT_TOKEN; ...` and not the token value
(`docs/evidence/detection/captures/falcosidekick-events.png`).

**Proof** (`docs/evidence/secrets/`):

| Test | Result |
| --- | --- |
| SecretStore status | `Valid`, `Ready=True` |
| Owner of `db-creds` | `ExternalSecret/db-creds` |
| Password in the Git repository | 0 occurrences |
| Vault token with no policy reads the secret | **denied** |
| Login to role `eso` with `eso-vault` (zt-data) | allowed |
| Login to role `eso` with a stolen `sa-frontend` token | **denied** |
| Login to role `eso` with `sa-attacker` | **denied** |
| `get secret db-creds` by every application ServiceAccount | `no` |
| Rotation: SHA-256 prefix before / target / after | `bb198728…` / `1fcf14ae…` / `1fcf14ae…` |
| TCP login to PostgreSQL with the synchronised password | OK |
| Vault UI: version history | 3 versions (initial copy + 2 rotations) |

The rotation script changes the password in PostgreSQL, writes a new KV version,
forces an ESO sync, waits until the Secret holds the new value, then verifies a real
TCP connection. It exits with an error if any step fails, so it can be used in
automation. Evidence files contain only hash prefixes, never the password.

**Observed failure behaviour.** After a VM reboot, Vault starts sealed. ESO's first
attempts fail (`SecretSyncedError`), yet the application keeps working: thanks to
`deletionPolicy: Retain` the last good value of `db-creds` stays in place. As soon as
Vault is unsealed, a forced sync brings the ExternalSecret back to `SecretSynced`.
`secrets/vault-unseal.sh` now triggers that sync itself.

**Comparison of approaches** (required by the secrets topic, used to justify our choice):

| Criterion | Native Secret | Vault + Agent sidecar | Vault + ESO (chosen) |
| --- | --- | --- | --- |
| Source of truth | cluster datastore | Vault | Vault |
| Stored in the cluster datastore | yes (base64, encrypted at rest only if enabled) | no | yes, as a copy |
| Application changes | none | annotations, file-based reading | none |
| Network flow from workloads to Vault | n/a | yes, from every pod | **no**, only the ESO controller |
| Rotation and history | manual, none | yes | yes (KV versions + refresh) |
| Extra components | none | injector webhook + one sidecar per pod | one operator |
| Main risk | anyone with `get secrets` | injector webhook, many Vault clients | ESO controller can read and write the Secrets of its namespace |

**Limits.**
- The final Secret still lives in the cluster datastore (SQLite on single-node k3s, not etcd). Its protection depends on RBAC and on encryption at rest (4.6).
- The ESO controller is scoped to `zt-data` (`scopedRBAC`, `scopedNamespace`, `processCluster*` disabled), a change made after A's cross-review (A1). Its access to Secrets in `kube-system`, `vault` and `zt-api` went from `yes` to `no` on both clusters (`docs/evidence/secrets-policy/eso-scoped-rbac-zt-lab-a.txt`, `docs/evidence/review/retest-a1-a2-zt-lab-b.txt`). It can still read and write every Secret of `zt-data`: compromising ESO still exposes `db-creds`.
- Running pods keep the old password in their environment until restarted. Application-side reloading, or Vault dynamic database credentials, would close this gap.
- Lab shortcuts: TLS disabled inside the cluster, a single unseal key, a single replica, the root token kept on the admin machine and used by the scripts, and **no auto-unseal**. On `zt-lab-a`, after a restart of the Vault pod, Vault stayed sealed and ESO stayed in `SecretSyncedError` for about 160 minutes until a manual unseal; the application kept working with the last value.
- Closing the chain (issue #16): A added `admission/70-secrets-only-from-eso.yaml`, which rejects any Secret in `zt-data` not written by the ESO controller, and default-deny NetworkPolicy for `vault` and `external-secrets` (`network/40-vault-eso.yaml`). On `zt-lab-b`, ESO still syncs through these policies and the attacker pod can no longer reach Vault (`docs/evidence/network-vault-falco/results-zt-lab-b.txt`).

### 4.6 Traceability and detection: audit, encryption at rest, Falco (B)

#### 4.6.1 Kubernetes API audit

**Design** (`cluster/audit/audit-policy.yaml`, loaded through a k3s drop-in file so the
shared `cluster/k3s-config.yaml` is untouched):

| Resource | Level | Reason |
| --- | --- | --- |
| Events, leases, health endpoints, Kyverno PolicyReports | None | Noise |
| Secrets, ConfigMaps, ServiceAccount tokens, ExternalSecrets | **Metadata** | Who, what, when, but **never the content** |
| `pods/exec`, `attach`, `portforward`, ephemeral containers | Metadata | The URL already contains the command executed |
| Writes on pods, ServiceAccounts, RBAC, NetworkPolicy, Cilium, Kyverno, admission webhooks | RequestResponse | Full body of security-relevant changes |
| Everything else | Metadata | |

**Proof** (`docs/evidence/audit/results-zt-lab-b.md`):
- S1: an `exec` in the frontend is recorded with user, pod and command (`command=sh&command=-c&command=id`).
- S2/S4: the stolen `sa-frontend` identity reading `db-creds` is recorded with **code 403**. The ESO controller's legitimate reads (code 200) are visible too.
- S3: pod creation records the user, the image (`curlimages/curl:8.10.1`) and the ServiceAccount requested, followed by the deletion.
- The base64 value of the password appears **0 times** in the log.

**Limits.** The log stays on the node, with rotation at 50 MB × 3 files. A root attacker on
the node can erase it. Shipping it to an external SIEM is the next step.

#### 4.6.2 Encryption of Secrets at rest

**Design.** k3s `secrets-encryption` (AES-CBC) enabled on an existing cluster:
`k3s secrets-encrypt enable`, restart, `rotate-keys` to re-encrypt every Secret, then
restart. On a new cluster the drop-in `cluster/audit/k3s-secrets-encryption.yaml` enables
it from the first start.

**Proof** (`docs/evidence/etcd-encryption/`). A test Secret containing a marker is read
directly from the k3s datastore (`state.db`), so that no real password is exposed:

| | Before | After |
| --- | --- | --- |
| Status | Disabled | Enabled, key `aescbckey-2026-11-06T20:01:30` |
| Marker readable in the datastore | **1** | **0** |
| Stored value starts with | `k8s` (plain object) | `k8s:enc:aescbc:v1:` |
| Readable through the API | yes | yes (transparent to applications) |

**Limits.** The key lives on the same node (`/var/lib/rancher/k3s/server/cred/`).
Encryption protects a stolen copy of the datastore or a backup, not a compromised
node. Losing the key makes every Secret unreadable, so the `cred` directory must be backed up.

#### 4.6.3 Runtime detection with Falco

**Design.** Falco 0.45.2 with the `modern_ebpf` driver (no kernel module to build), the
container plugin reading `/run/k3s/containerd/containerd.sock` so that every alert
carries its namespace and pod, Falcosidekick and its UI (1 replica each to save memory).
Five custom rules are tied to the scenarios and tagged with MITRE ATT&CK
(`detection/falco-values.yaml`):

| Rule | Scenario | ATT&CK | Priority |
| --- | --- | --- | --- |
| ZT Shell spawned in app container | S1 | T1059 | Warning |
| ZT Read of service account token | S2 | T1528 | Warning |
| ZT Outbound connection from data tier | S1/S4 exfiltration | T1041 | Notice |
| ZT Interactive access to secrets tooling | S4 | T1552 | Critical |
| ZT Read of Vault storage by non-vault process | S4 | T1552.001 | Critical |

The outbound rule deliberately does not reuse Falco's `outbound` macro, which ignores
failed connections and private addresses. Ours also reports attempts that NetworkPolicy
blocks, so the same attack is both **prevented** (Cilium) and **detected** (Falco).

**Tuning (false positive).** As soon as it was deployed, the Vault rule fired every
5 seconds: the Vault chart's readiness probe runs `sh -ec vault status -tls-skip-verify`.
We added a documented exception (macro `zt_vault_probe`) and removed a condition on
`evt.dir` that Falco 0.45 reports as deprecated. Result: from one false alert every 5 s to none.

**Proof** (`docs/evidence/detection/`): all five rules fire with the correct namespace and pod
(`alerts-zt-lab-b.tsv`). The Falcosidekick UI shows the alerts by priority and by MITRE tag
(`captures/`). With A's NetworkPolicy for the `falco` namespace (`network/50-falco.yaml`),
alerts still reach Falcosidekick, Falco restarts and downloads its rules under default
deny, and a connection from the database to the Internet is both **blocked** and
**detected** (`docs/evidence/network-vault-falco/results-zt-lab-b.txt`).

**Hardening after kube-bench.** Falco reads container metadata through the containerd
socket and does not call the Kubernetes API, so its four pods no longer mount a
ServiceAccount token (`scripts/harden-serviceaccounts.sh`). Alerts still carry namespace
and pod after the change.

**Limits.**
- Falco detects but **does not block**. It complements prevention, it does not replace it.
- The shell rule watches shell names only: `curl`, `wget` or `nc` run directly through `kubectl exec` raise no Falco alert. The audit log still records every `exec` with its command (A3).
- The shell rule first excluded any command containing `docker-entrypoint`, so an attacker could evade it by writing that string into his own command (A2, found by A). Container starts launch no shell (0 alert on both clusters), so the exclusion was removed: the bypass now alerts (`docs/evidence/detection/a2-docker-entrypoint-zt-lab-a.txt`, `docs/evidence/review/retest-a1-a2-zt-lab-b.txt`).
- The Falco pod is privileged, with kernel access and the containerd socket: it is a new, high-value attack surface.
- The probe exception is based on the command line: an attacker who includes `vault status` in a command evades the Vault shell rule.
- The Falcosidekick UI no longer accepts the chart's default `admin:admin`: its credentials come from a Secret created by hand, outside Git (`falcosidekick-ui-credentials`). The chart's own Secret still contains the default value and is overridden only because ours is loaded last (Kubernetes `envFrom` precedence). `admin:admin` must be re-tested after every chart upgrade (`docs/evidence/detection/ui-credentials-zt-lab-b.txt`).
- The `falco` namespace allows HTTPS to any destination for the Falco pod, so that falcoctl can download rules from changing CDN addresses. A rule pinned by domain name would be stricter.
- Without monitoring of Falco itself, a stopped Falco is a silent blind spot.

## 5. Blast radius after compromise of the frontend

Source: `docs/evidence/blast-radius.md`, produced by `scripts/measure.sh` at each phase (cluster `zt-lab-a`).

| Stage | API | Database | Kubernetes API | Internet | Read secrets (zt-data) | Create pods | S3 dangerous pod | S4 secret |
|---|---|---|---|---|---|---|---|---|
| Baseline | reachable | reachable | reachable | reachable | yes | yes | accepted | readable |
| + RBAC | reachable | reachable | reachable | reachable | no | no | accepted | not readable |
| + NetworkPolicy | reachable | blocked | blocked | blocked | no | no | accepted | not readable |
| + PSA | reachable | blocked | blocked | blocked | no | no | rejected | not readable |
| + Kyverno | reachable | blocked | blocked | blocked | no | no | rejected | not readable |
| Integration (+ Vault/ESO + Falco) | reachable | blocked | blocked | blocked | no | no | rejected | not readable |

What Vault/ESO and Falco add is not visible in these columns, because they reduce other
risks: who can obtain the secret, whether it rotates, and whether an attack is noticed.
Their effect is measured in 4.5 and 4.6.

The integration row is the replay of S1–S4 on `zt-lab-a` with every layer active
(`docs/evidence/integration/`). It shows that adding Vault, ESO and Falco did not weaken
any earlier control.

The same replay on `zt-lab-b` (Ubuntu 24.04, kernel 6.14) gives an **identical** result,
line by line (`docs/evidence/integration/results-zt-lab-b.md`). Integration surfaced one
undocumented manual step: Kyverno chart 3.9.2 disables PolicyExceptions by default, so
`features.policyExceptions.enabled=true` and `features.policyExceptions.namespace=kyverno`
must be set at install time for `admission/60-policy-exception.yaml` to work.

## 6. Compliance

**kube-bench** (CIS `k3s-cis-1.9`, v0.16.0, zt-lab-a): 59 PASS and 4 FAIL after two fixes (PKI certificate permissions, default ServiceAccounts without token). The 4 remaining findings are analysed in `docs/evidence/final/kube-bench-analysis.md`: two false positives on the CNI file path, one not applicable (k3s uses SQLite, not etcd), one justified (system components need their token).
`zt-lab-b` gives the same result, from 57 PASS / 6 FAIL before to 59 PASS / 4 FAIL after
the same fixes (`docs/evidence/kube-bench/README.md`). The two clusters therefore agree,
although they run different operating systems (Debian 13 and Ubuntu 24.04).

Kubescape v4.0.20 (NSA and MITRE frameworks, 38 of 40 controls evaluated) found one real defect on our workloads: C-0013 (non-root containers) on frontend, api and attacker, caused by a missing `runAsGroup`. It was fixed in `app/` and the `zt-*` namespaces now show no failed control (NSA 68.07 to 68.75, MITRE 65.11). The remaining failures come from third-party charts (Kyverno, External Secrets Operator, Falco, Vault) or are false positives (Kyverno's own webhooks flagged as a risk by C-0036 and C-0039); analysis in `docs/evidence/final/kubescape-analysis.md`.

**Trivy** v0.76.2 (images read directly from containerd on zt-lab-b, HIGH and CRITICAL only) found 222 vulnerabilities in the four application images: nginx-unprivileged 65 (3 critical), podinfo 107 (6 critical, most of them in its two Go binaries), postgres 26 (1 critical) and curl 24 (2 critical). **Every one of them has a fixed version**, and none comes from the cluster configuration. For nginx-unprivileged, podinfo and curl the cause is an old base OS (Alpine 3.20.3 or 3.21.3), plus Go binaries built with Go 1.23.2 in podinfo; for postgres the OS is recent (Alpine 3.24.4, no HIGH or CRITICAL finding) and all 26 findings come from one embedded Go binary, `gosu`, built with Go stdlib v1.24.6. The critical ones are OpenSSL CVE-2026-31789 (described by Trivy as a heap overflow on 32-bit systems, while our node is x86_64), brotli, the Go standard library and gRPC. They are accepted for the lab: changing versions a few days before delivery would invalidate the measurements, the rebuild and Kyverno's image allowlist. The controls of sections 4.3 to 4.6 limit what an exploit could do (non-root, read-only root filesystem, a single allowed flow, no token, Falco). Analysis and production recommendations (update and pin by digest, Trivy in CI, periodic rescans): `docs/evidence/final/trivy-analysis.md`.

## 7. Storage security

| Data | Type | Storage | Protection |
| --- | --- | --- | --- |
| PostgreSQL data | persistent | PVC `db-data` 1 Gi, StorageClass `local-path` | Non-root pod (`fsGroup: 70`, the postgres group, owns the volume), no other pod mounts it, network access only from the API |
| Vault Raft data and audit log | persistent | 2 PVCs (2 Gi data, 1 Gi audit), `local-path` | Data encrypted by Vault (barrier key), readable only after unseal |
| Falcosidekick UI (Redis) | persistent | PVC, `local-path` | Alerts only, no secrets |
| Frontend `/tmp`; database `/tmp` and `/var/run/postgresql` | ephemeral | `emptyDir` | Root filesystem is read-only in every application pod: only these `emptyDir` volumes are writable, and they disappear with the pod |
| nginx configuration | read-only | ConfigMap `frontend-nginx` | Mounted read-only, changed only through Git |
| Kubernetes Secrets | persistent | k3s datastore | Encrypted at rest with AES-CBC (4.6.2) |

**Provisioner.** k3s ships the `local-path` provisioner (`rancher.io/local-path`). It is a
dynamic provisioner, not a full CSI driver: when a PVC is created, it creates a directory
under `/var/lib/rancher/k3s/storage/` on the node and mounts it into the pod. A CSI
driver (Longhorn, a cloud disk) would add replication, snapshots and encryption.

**Why hostPath is dangerous.** A `hostPath` volume mounts a directory of the **node**
into the container. With `hostPath: /` (the S3 test pod) the container can read
`/etc/shadow` and the k3s credentials under `/var/lib/rancher/k3s/server`, including the
encryption key from 4.6.2, write to `/etc/cron.d` or the containerd socket, and so take
over the node and every workload on it. PSA `restricted` rejects `hostPath`
in application namespaces (`docs/evidence/admission-psa/`). Note that `local-path` itself relies on node directories: the
isolation comes from the provisioner choosing the path, not the user.

**Volume types.** None of our Kyverno policies restricts volume types: that control belongs to Pod Security Admission. The `restricted` profile only allows `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` and `secret` volumes, and the application namespaces enforce it. Evidence: the S3 pod with `hostPath: /` is refused (`docs/evidence/admission-psa/`).

## 8. Security analysis: the six questions of section 2.6

**1. Which components are the most sensitive?**
In order: the **kube-apiserver and its datastore** (they control everything), **Vault and
its unseal key** (every application secret), the **ESO controller** (scoped to `zt-data` since the
review, where it can still write every Secret), and the **privileged node agents, Cilium and Falco** (kernel access). Among
applications, the **database**, which holds the data and the most valuable credential.

**2. Which permissions does each component need?**
Application workloads need **no Kubernetes API permission at all**: no token is mounted.
ESO needs read/write on Secrets of `zt-data` only (scoped RBAC) and a TokenRequest for `eso-vault`. Kyverno's background controller needs to create and delete NetworkPolicies to generate the default deny. Vault needs
`system:auth-delegator` to validate tokens. Falco needs read access to the runtime socket
and the kernel. Details: section 4.2 and 4.5.

**3. What can be reached after a pod is compromised?**
Measured for the frontend (section 5): in the baseline, every service, the Kubernetes API
and the Internet, plus every secret of `zt-data`. With all layers: **only the API on port 9898**,
the legitimate flow, with no token to talk to Kubernetes, and no way to log into Vault even
with a stolen token. Remaining risk: abusing the API itself (section 9). Confirmed on both clusters rebuilt from scratch: the measurement is identical (`docs/evidence/rebuild/results-zt-lab-a.md`, `results-zt-lab-b.md`).

**4. What prevents or limits lateral movement?**
Default-deny NetworkPolicy enforced by Cilium (network), the absence of tokens and
minimal RBAC (Kubernetes API), Vault roles bound to one identity (secrets), PSA and
Kyverno against escape to the node (admission). Falco and the audit log do not prevent
movement, they make it **visible**.

**5. What are the risks of a bad volume configuration?**
`hostPath` exposes the node filesystem (section 7). A writable root filesystem lets an
attacker drop tools. A PVC mounted by several pods can expose data to another workload, and wrong
ownership (no `fsGroup`) pushes operators to run the database as root. An unencrypted datastore leaks every Secret from a backup.
Our controls: PSA/Kyverno, read-only root filesystem with `emptyDir` only where writing
is needed, one PVC per component with `fsGroup`, and encryption at rest.

**6. What are the limits of the controls?**
See section 9. In short: everything runs on a **single node**, so a node compromise
defeats every control. The legitimate frontend → API flow remains open. Several tools
run with lab shortcuts (Vault without TLS, a single unseal key, the root token kept on the admin machine). The application images carry known vulnerabilities, all fixable by an update (section 6). Detection is not prevention.


## 9. Limits and residual risks

| Area | Residual risk | Possible improvement |
| --- | --- | --- |
| Whole cluster | Single node: compromising the node defeats every control | Several nodes, node hardening, kube-bench findings |
| Application | The frontend can still abuse the API (legitimate flow) | Cilium L7 policy in production, API authentication |
| Admission | Kyverno runs with a single replica: a clean stop removes its webhooks (fail-open), a crash blocks every pod creation for about 30 s (fail-closed) | Three replicas with a PodDisruptionBudget, alert when the webhooks disappear |
| Admission (scope) | Ephemeral containers escape the image rules; Kyverno's background controller can delete NetworkPolicies cluster-wide; the token mutation is a default, not a control | A rule on the `ephemeralcontainers` subresource, narrower generate permissions, a validate rule on `automountServiceAccountToken` |
| Network | No pod-to-pod encryption (WireGuard shown only as an option); the frontend is reachable only through `kubectl port-forward`; DNS can carry exfiltration | Cilium transparent encryption, or a service mesh with mTLS; a Cilium DNS rule; a real ingress |
| Secrets | ESO is scoped to `zt-data` since the review (A1) but can still write every Secret there; pods keep old passwords until restart | Vault dynamic database credentials, automatic restart |
| Vault | TLS off, one unseal key, root token on the admin machine | TLS, auto-unseal with a KMS, revoke the root token after setup |
| Encryption at rest | Key stored on the same node | KMS provider |
| Audit | Log kept on the node only | Ship to a SIEM |
| Images (supply chain) | 222 HIGH/CRITICAL vulnerabilities in the four application images, all with a fixed version; tags are not pinned by digest | Update the tags, pin by digest in the manifests and in Kyverno, Trivy in CI (`--exit-code 1 --severity CRITICAL --ignore-unfixed`), periodic rescans, a minimal image without `podcli` for the API |
| Detection | Falco detects but does not block; command-line based exceptions; UI credentials rely on `envFrom` order; Falco pod allowed HTTPS to any destination | Response through Falco Talon or Tetragon enforcement; tighter exceptions; chart-native secret handling; FQDN egress rule |

## 10. Answer to the central question

> How can the Zero Trust principle be applied to Kubernetes workloads without
> multiplying security mechanisms unnecessarily?

Our answer: **start with the native mechanisms, then add a tool only when a measured
risk remains.** Each tool below is justified by the risk it removes, checked against
what the previous layers already do, and accepted with the attack surface it adds.

| Tool | Risk reduced (measured) | Already covered by? | New attack surface | Cost | If it fails |
| --- | --- | --- | --- | --- | --- |
| RBAC + no token (native) | S2/S4: 96 → 23 rules, no secret access | nothing, first layer | none | none | n/a |
| NetworkPolicy (native) | S1: 4 reachable targets → 1 | nothing at L3/L4 | none | none (needs a CNI) | depends on the CNI |
| Cilium + Hubble | Enforces NetworkPolicy; adds L7 and flow visibility | partly (L3/L4 by any CNI) | privileged eBPF agent | 303 MiB, 54 m CPU | no pod networking |
| PSA (native) | S3: privileged/hostPath rejected | nothing | none | none | n/a, built into the API server |
| Kyverno | What PSA cannot express (tags, limits, images, generated default deny) | partly (S3 already by PSA) | admission webhook with cluster-wide rights | memory, policy maintenance | fail-open on a clean stop, fail-closed for about 30 s on a crash (measured, section 4.4) |
| Vault + ESO | S4: secret owned, versioned, rotated, unusable with a stolen token | partly (RBAC already hides it) | Vault, unseal key, ESO controller | 170 MiB, 38 m CPU | Vault sealed: ESO in `SecretSyncedError`, existing Secret kept, app unaffected (observed after a reboot) |
| Audit + encryption at rest (native k3s) | Traceability; S4 from a stolen backup | nothing | log volume, key on node | disk | loss of traceability; key loss = unreadable Secrets |
| Falco | Visibility of S1, S2 and S4 attempts, even when blocked | nothing (detection) | privileged pod, kernel access | 116 MiB, 29 m CPU | silent blind spot |

**Where we deliberately did not add more.** Cilium L7 rules are kept as a demonstration
instead of covering every flow, because NetworkPolicy already closes S1 and L7 would tie
every manifest to Cilium. Kyverno does not duplicate the PSA rules. There is no service
mesh, because its main benefit (mTLS) is not measured by our scenarios and Cilium can
provide transparent encryption more cheaply.

Measured on `zt-lab-b` with `kubectl top pods -A` (6 November 2026, idle lab, all pods of each tool added up):

| Tool | Pods | CPU | Memory |
| --- | --- | --- | --- |
| Application (frontend, API, database) | 3 | 6 m | 35 MiB |
| Cilium + Hubble (agent, Envoy, operator, relay, UI) | 5 | 54 m | 303 MiB |
| External Secrets Operator (controller, webhook, cert-controller) | 3 | 6 m | 124 MiB |
| Vault | 1 | 32 m | 46 MiB |
| Falco + Falcosidekick + UI + Redis | 4 | 29 m | 116 MiB |
| Kyverno (admission, background, cleanup and reports controllers) | 4 | 91 m | 306 MiB |

The security tooling uses **about 26 times more memory than the application it
protects** (≈ 895 MiB against 35 MiB with Kyverno, ≈ 590 MiB without it). On a real cluster this cost is shared by many
applications, but it confirms that each tool must earn its place: Cilium is the most
expensive, and it is also the one that enforces every network control.

## 11. Reproducibility

The `README.md` rebuilds the lab from an empty VM. Versions are pinned in
`versions.md`. Every proof cited here is a file under `docs/evidence/` produced by a
script in the repository. No secret is stored in Git: Gitleaks runs on every commit, and
the Vault unseal material is excluded by `.gitignore`.

**Rebuild test.** On 8 November 2026 zt-lab-a was destroyed (`k3s-uninstall.sh`, reboot) and rebuilt by following only the README, in 47 minutes. The six acceptance criteria were met: node ready and Cilium healthy, the 6 Kyverno CLI tests, R1 and R10 refused, ESO synchronised and scoped to `zt-data`, the Falco alert on the bypass with no false alert at container start, and a blast-radius measurement identical to the original cluster. The rebuild found three gaps in the README (copying the kubeconfig, the initial `db-creds` Secret, the Kyverno wait on a slow link), fixed in commit `2549f76`. Journal and proofs: `docs/evidence/rebuild/`.

The same test was run on zt-lab-b the same day, following the README as fixed by A, in 55 minutes from the first README step to the measurement; step 2 (k3s and the import of the preloaded images) took 21 of them and Vault 13, because its image had to be downloaded over a 4G link. **All six criteria were met again**, and the blast-radius measurement is identical both to the original zt-lab-b and to zt-lab-a. This second rebuild, on another operating system and by the other team member, found three more gaps: the README does not list the tools to install first (Kyverno CLI, Helm, Cilium CLI); `k3s-uninstall.sh` leaves `/etc/cni/net.d`, so the node reports `Ready` before Cilium is installed; and `secrets/vault-unseal.sh` waited only 180 s for the Vault pod, too short on a slow link (raised to 600 s in commit `b3451c7`). The two README gaps were fixed by A in commit `88b5e34`, so each rebuild found different gaps and all of them are now closed. One deviation is declared: the images already downloaded were preloaded through the k3s air-gap directory to save bandwidth, without changing any version or setting. Journal and proofs: `docs/evidence/rebuild/rebuild-zt-lab-b.md`, `criteres-zt-lab-b.txt`.

## Appendix A: evidence index

| Section | Evidence |
| --- | --- |
| 2 | `docs/architecture/` (diagrams) |
| 4.1 | `docs/evidence/baseline/`, `docs/evidence/phase-1/networkpolicy-check/` |
| 4.2 | `docs/evidence/rbac/` |
| 4.3 | `docs/evidence/network/` (including `api-to-database-zt-lab-a.txt`), `docs/evidence/cilium-l7/`, `docs/evidence/network-after-l7/`, `docs/evidence/network-vault-falco/` |
| 4.4 | `docs/evidence/admission-psa/`, `docs/evidence/admission-kyverno/`, `docs/evidence/kyverno-extra/` |
| 4.5 | `docs/evidence/secrets/` (results, rotation, `captures/`) |
| 4.6 | `docs/evidence/audit/`, `docs/evidence/etcd-encryption/`, `docs/evidence/detection/` |
| 5 | `docs/evidence/blast-radius.md`, `docs/evidence/integration/` |
| 4.4 (failure modes) | `docs/evidence/fail-mode/` |
| Cross-reviews | `docs/reviews/`, `docs/evidence/review/`, `docs/evidence/secrets-policy/` (R10, A1) |
| 6 | `docs/evidence/final/` (kube-bench, Kubescape, Trivy), `docs/evidence/kube-bench/` |
| 11 | `docs/evidence/rebuild/` |
