# Reproduce: secrets, audit, encryption at rest and detection

Part B of the rebuild (Doha El Merabet). It plugs into the main `README.md` sequence, which
follows the guide §7.3 order:

1. k3s + Cilium (README), **with the audit and encryption files of step 1 below copied first**
2. `app/` and `rbac/` (README)
3. **Vault and External Secrets Operator** (steps 2 and 3 below)
4. **Falco** (step 4 below)
5. `network/`, Pod Security labels, Kyverno and `admission/` (README)
6. **ServiceAccount hardening and checks** (steps 5 and 6 below)

Versions come from [`versions.md`](../versions.md). Run every command from the repository
root. Two files hold secrets and stay **outside Git**, in your home directory:
`~/vault-init.json` (Vault root token and unseal key) and `~/falcosidekick-ui.txt`
(Falcosidekick UI login). Both are covered by `.gitignore` patterns or live outside the
repository. Never print them, never commit them.

## 1. API audit and Secret encryption at rest (before installing k3s)

The datastore of this single-node k3s is **SQLite** (kine, `/var/lib/rancher/k3s/server/db/state.db`),
not etcd. The files below are k3s drop-ins, so the shared `cluster/k3s-config.yaml` stays unchanged.

```bash
sudo mkdir -p /etc/rancher/k3s/config.yaml.d /var/lib/rancher/k3s/server/logs
sudo cp cluster/audit/audit-policy.yaml /var/lib/rancher/k3s/server/audit-policy.yaml
sudo cp cluster/audit/k3s-audit.yaml /etc/rancher/k3s/config.yaml.d/20-audit.yaml
sudo cp cluster/audit/k3s-secrets-encryption.yaml /etc/rancher/k3s/config.yaml.d/30-secrets-encryption.yaml
# then install k3s as described in the README
```

Check once k3s runs:

```bash
sudo ls -l /var/lib/rancher/k3s/server/logs/audit.log
sudo k3s secrets-encrypt status          # Encryption Status: Enabled
```

On a cluster that already runs without encryption, use instead:
`sudo k3s secrets-encrypt enable`, copy the drop-in, restart k3s, `sudo k3s secrets-encrypt rotate-keys`,
wait for `reencrypt_finished`, restart k3s again (proof: `docs/evidence/etcd-encryption/`).

## 2. Vault (Raft storage, no dev mode)

Prerequisite: the initial `db-creds` Secret created by hand in `zt-data` (README, application
step). Vault copies its value, so it must exist **before** Kyverno policy
`admission/70-secrets-only-from-eso.yaml` is applied.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com && helm repo update
helm install vault hashicorp/vault -n vault --create-namespace \
  --version 0.34.1 -f secrets/vault-values.yaml
kubectl -n vault get pods                 # vault-0 0/1: normal, it starts sealed

./secrets/vault-unseal.sh                 # first run: init, writes ~/vault-init.json (mode 600), unseals
./secrets/vault-configure.sh              # audit device, KV v2, policy zt-database-read, Kubernetes auth role eso
```

After every reboot of the VM, Vault is sealed again: run `./secrets/vault-unseal.sh`. It
also forces an ESO resync.

## 3. External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io && helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --version 2.14.0 --set installCRDs=true
kubectl -n external-secrets wait --for=condition=Ready pod --all --timeout=5m

kubectl apply -f secrets/10-secretstore.yaml
kubectl -n zt-data get secretstore vault  # STATUS Valid, READY True

# ESO refuses to adopt a Secret it did not create: delete the hand-made one,
# its value is already in Vault, then let ESO recreate and own it.
kubectl -n zt-data delete secret db-creds
kubectl apply -f secrets/20-externalsecret-db.yaml
kubectl -n zt-data get externalsecret db-creds   # SecretSynced, True
kubectl -n zt-data rollout restart deploy/database
```

## 4. Falco, Falcosidekick and its UI

Docker Hub can be slow on a weak connection. Pre-pulling the images one by one avoids a
stalled parallel download:

```bash
for img in falcosecurity/falco:0.45.2 falcosecurity/falcoctl:0.14.3 \
           falcosecurity/falcosidekick:2.35.1 falcosecurity/falcosidekick-ui:2.2.0 \
           redis/redis-stack-server:7.2.0-v11; do
  sudo k3s crictl pull "docker.io/$img"
done
```

The UI login comes from a Secret created by hand (never in Git). Create it **before** the chart:

```bash
kubectl create namespace falco
( umask 077; printf 'admin:%s' "$(openssl rand -base64 18 | tr -d '/+=')" > ~/falcosidekick-ui.txt )
kubectl -n falco create secret generic falcosidekick-ui-credentials \
  --from-file=FALCOSIDEKICK_UI_USER=/dev/stdin < ~/falcosidekick-ui.txt

helm repo add falcosecurity https://falcosecurity.github.io/charts && helm repo update
helm install falco falcosecurity/falco -n falco \
  --version 9.2.2 -f detection/falco-values.yaml
kubectl -n falco rollout status ds/falco --timeout=6m
kubectl -n falco logs ds/falco -c falco | grep -i "runtime socket"   # must list /host/run/k3s/containerd/containerd.sock
```

Install Falco **after** the k3s restarts of step 1. If k3s restarts later, run
`kubectl -n falco rollout restart ds/falco`, otherwise Falco keeps a stale containerd socket and
alerts lose their namespace and pod.

## 5. ServiceAccount hardening (last, after Kyverno)

```bash
./scripts/harden-serviceaccounts.sh
```

It disables token automount on the `default` ServiceAccount of every namespace that exists
when it runs, removes the token from the Falco pods, and sets the k3s certificates to mode 600
(kube-bench 5.1.5, 5.1.6 and 1.1.20). Run it **after** every namespace exists, Kyverno
included, and again after adding a namespace.

## 6. Checks

```bash
./secrets/rotate-db-password.sh           # exit code 0, hash after = target hash
./secrets/verify-secrets.sh               # sa-frontend and sa-attacker cannot log into Vault
kubectl -n zt-frontend exec deploy/frontend -- sh -c id
kubectl -n falco logs ds/falco -c falco --since=1m | grep '"rule":"ZT Shell'
./scripts/measure.sh integration          # must match docs/evidence/integration/results-zt-lab-a.md
```

Expected results and evidence: `docs/evidence/secrets/`, `docs/evidence/detection/`,
`docs/evidence/network-vault-falco/`, `docs/evidence/kube-bench/`, `docs/evidence/integration/`.
