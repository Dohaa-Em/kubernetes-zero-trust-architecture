# Zero Trust for Kubernetes Workloads: Design, Implementation and Measured Results

**Mini-project 1: Securing Kubernetes workloads with a Zero Trust approach**

| | |
| --- | --- |
| Authors | Abir Majdi (A), Doha El Merabet (B) |
| Repository | `penelopeeckhar/kubernetes-zero-trust-architecture` |
| Clusters | `zt-lab-a` (Debian 13), `zt-lab-b` (Ubuntu 24.04), k3s v1.36.5+k3s1, single node |
| Writing | B (this document), review by A |
| Status | Draft of 6 November 2026. Sections marked **TODO** are completed after integration (phase 7) and measurements (phase 8). |

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

> **TODO (B, phase 8):** architecture diagrams in `docs/architecture/`: before/after,
> allowed flows, Vault/ESO flows.

### 2.3 Flows

| Flow | Allowed | Control |
| --- | --- | --- |
| frontend → api:9898 | yes | NetworkPolicy `allow-frontend-to-api` |
| api → database:5432 | yes | NetworkPolicy `allow-api-to-database` |
| all pods → CoreDNS:53 | yes | `allow-dns-egress` |
| frontend → database, frontend → Kubernetes API, any pod → Internet | **no** | default deny ingress and egress |
| ESO → Vault:8200, Vault → kube-apiserver (TokenReview) | yes | `docs/flows-vault-eso.md` |
| Falco → Falcosidekick:2801 → UI:2802 → Redis:6379 | yes | `docs/flows-falco.md` |

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

> **TODO (A):** table permission / component / reason, and list of dangerous permissions checked.

Measured effect (`docs/evidence/rbac/`): the baseline `edit` binding is removed, tokens
are no longer mounted (`automountServiceAccountToken: false` on every ServiceAccount
and pod), and the rules available to `sa-frontend` in `zt-data` drop from **96 to 23**
(default discovery rules only). Reading secrets, creating pods and `pods/exec` are all
denied. S2 and S4 are closed at the Kubernetes API level.

### 4.3 Network: NetworkPolicy and Cilium (A)

> **TODO (A):** flow matrix and Hubble captures of each blocked flow.

Default deny ingress and egress in every application namespace, explicit DNS, then one
policy per legitimate flow. After this phase the frontend still reaches the API (a
legitimate flow) but no longer the database, the Kubernetes API or the Internet
(`docs/evidence/network/`). A CiliumNetworkPolicy demonstrates L7 filtering
(`GET /healthz` forwarded, `GET /version` denied). It is kept as a demonstration only, to
avoid tying every flow to Cilium (`docs/architecture-networkpolicy-vs-cilium.md`).

### 4.4 Admission: Pod Security Admission and Kyverno (A)

> **TODO (A):** rule list with audit → enforce history and the fail-open/fail-closed test.

All application namespaces enforce Pod Security `restricted`, which rejects the S3
privileged/hostPath pod even before Kyverno is involved. Kyverno adds what PSA cannot
express: no `latest` tag, mandatory resource limits, an image allowlist, mutation of
secure defaults, and generation of a default-deny NetworkPolicy for every new `zt-*`
namespace (with the ClusterRole that Kyverno's background controller needs for it). A documented PolicyException covers system namespaces
(`admission/`, `docs/evidence/admission-*`).

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
forces an ESO sync and verifies a real TCP connection. Evidence files contain only
hash prefixes, never the password.

**Comparison of approaches** (required by the secrets topic, used to justify our choice):

| Criterion | Native Secret | Vault + Agent sidecar | Vault + ESO (chosen) |
| --- | --- | --- | --- |
| Source of truth | etcd | Vault | Vault |
| Stored in etcd | yes (base64, encrypted at rest only if enabled) | no | yes, as a copy |
| Application changes | none | annotations, file-based reading | none |
| Network flow from workloads to Vault | n/a | yes, from every pod | **no**, only the ESO controller |
| Rotation and history | manual, none | yes | yes (KV versions + refresh) |
| Extra components | none | injector webhook + one sidecar per pod | one operator |
| Main risk | anyone with `get secrets` | injector webhook, many Vault clients | ESO controller can write Secrets cluster-wide |

**Limits.**
- The final Secret still lives in etcd. Its protection depends on RBAC and on encryption at rest (4.6).
- The ESO controller's ClusterRole allows reading and writing Secrets in every namespace: compromising ESO is equivalent to compromising every synchronised secret. Scoping it (`scopedNamespace`/`scopedRBAC`) is an improvement.
- Running pods keep the old password in their environment until restarted. Application-side reloading, or Vault dynamic database credentials, would close this gap.
- Lab shortcuts: TLS disabled inside the cluster, a single unseal key, a single replica, the root token kept on the admin machine.
- Issue #16 is still open: a Kyverno rule rejecting hand-made Secrets in `zt-data` (except from ESO), and NetworkPolicy for the `vault`, `external-secrets` and `falco` namespaces.

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
(`captures/`).

**Limits.**
- Falco detects but **does not block**. It complements prevention, it does not replace it.
- The Falco pod is privileged, with kernel access and the containerd socket: it is a new, high-value attack surface.
- The probe exception is based on the command line: an attacker who includes `vault status` in a command evades the Vault shell rule.
- Falcosidekick UI uses the chart's default credentials (`admin:admin`) and is reachable only through `port-forward`. This must change before any real use.
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
| + Vault/ESO | | | | | | | | **TODO (phase 7)** |
| + Falco | | | | | | | | **TODO (phase 7)** |

What Vault/ESO and Falco add is not visible in these columns, because they reduce other
risks: who can obtain the secret, whether it rotates, and whether an attack is noticed.
Their effect is measured in 4.5 and 4.6.

> **TODO (A and B, phase 7):** final replay of S1–S4 on both clusters with every layer applied.

## 6. Compliance

> **TODO (phase 8):** kube-bench (CIS k3s profile) and Kubescape (NSA, MITRE) by A,
> Trivy image scan by B, results in `docs/evidence/final/`.

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
over the node and every workload on it. PSA `restricted` and Kyverno reject `hostPath`
in application namespaces. Note that `local-path` itself relies on node directories: the
isolation comes from the provisioner choosing the path, not the user.

> **TODO (A):** confirm the volume types allowed by Kyverno and add the evidence path.

## 8. Security analysis: the six questions of section 2.6

**1. Which components are the most sensitive?**
In order: the **kube-apiserver and its datastore** (they control everything), **Vault and
its unseal key** (every application secret), the **ESO controller** (can write Secrets in any
namespace), and the **privileged node agents, Cilium and Falco** (kernel access). Among
applications, the **database**, which holds the data and the most valuable credential.

**2. Which permissions does each component need?**
Application workloads need **no Kubernetes API permission at all**: no token is mounted.
ESO needs read/write on Secrets and a TokenRequest for `eso-vault`. Vault needs
`system:auth-delegator` to validate tokens. Falco needs read access to the runtime socket
and the kernel. Details: section 4.2 (TODO A) and 4.5.

**3. What can be reached after a pod is compromised?**
Measured for the frontend (section 5): in the baseline, every service, the Kubernetes API
and the Internet, plus every secret of `zt-data`. With all layers: **only the API on port 9898**,
the legitimate flow, with no token to talk to Kubernetes, and no way to log into Vault even
with a stolen token. Remaining risk: abusing the API itself (section 9).

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
run with lab shortcuts (no TLS, default credentials). Detection is not prevention.

> **TODO (phase 7):** confirm questions 2 and 3 against the final replay.

## 9. Limits and residual risks

| Area | Residual risk | Possible improvement |
| --- | --- | --- |
| Whole cluster | Single node: compromising the node defeats every control | Several nodes, node hardening, kube-bench findings |
| Application | The frontend can still abuse the API (legitimate flow) | Cilium L7 policy in production, API authentication |
| Network | No pod-to-pod encryption (WireGuard shown only as an option) | Cilium transparent encryption, or a service mesh with mTLS |
| Secrets | ESO controller has cluster-wide access to Secrets; pods keep old passwords until restart | Scoped ESO, Vault dynamic database credentials, automatic restart |
| Vault | TLS off, one unseal key, root token on the admin machine | TLS, auto-unseal with a KMS, revoke the root token after setup |
| Encryption at rest | Key stored on the same node | KMS provider |
| Audit | Log kept on the node only | Ship to a SIEM |
| Detection | Falco detects but does not block; command-line based exceptions; default UI credentials | Response through Falco Talon or Tetragon enforcement; tighter exceptions; credentials changed |

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
| Kyverno | What PSA cannot express (tags, limits, images, generated default deny) | partly (S3 already by PSA) | admission webhook with cluster-wide rights | memory, policy maintenance | fail-open or fail-closed (TODO A) |
| Vault + ESO | S4: secret owned, versioned, rotated, unusable with a stolen token | partly (RBAC already hides it) | Vault, unseal key, ESO controller | 170 MiB, 38 m CPU | Vault sealed: no new sync, existing Secrets kept |
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
| Kyverno | | | TODO (A, measured on `zt-lab-a`) |

The security tooling uses **about 17 times more memory than the application it
protects** (≈ 590 MiB against 35 MiB, without Kyverno). On a real cluster this cost is shared by many
applications, but it confirms that each tool must earn its place: Cilium is the most
expensive, and it is also the one that enforces every network control.

## 11. Reproducibility

The `README.md` rebuilds the lab from an empty VM. Versions are pinned in
`versions.md`. Every proof cited here is a file under `docs/evidence/` produced by a
script in the repository. No secret is stored in Git: Gitleaks runs on every commit, and
the Vault unseal material is excluded by `.gitignore`.

## Appendix A: evidence index

| Section | Evidence |
| --- | --- |
| 4.1 | `docs/evidence/baseline/`, `docs/evidence/phase-1/networkpolicy-check/` |
| 4.2 | `docs/evidence/rbac/` |
| 4.3 | `docs/evidence/network/`, `docs/evidence/cilium-l7/`, `docs/evidence/network-after-l7/` |
| 4.4 | `docs/evidence/admission-psa/`, `docs/evidence/admission-kyverno/`, `docs/evidence/kyverno-extra/` |
| 4.5 | `docs/evidence/secrets/` (results, rotation, `captures/`) |
| 4.6 | `docs/evidence/audit/`, `docs/evidence/etcd-encryption/`, `docs/evidence/detection/` |
| 5 | `docs/evidence/blast-radius.md` |
