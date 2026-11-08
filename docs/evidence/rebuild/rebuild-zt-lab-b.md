# Reconstruction depuis zéro — zt-lab-b (8 novembre 2026)

VM : Ubuntu 24.04, noyau 6.14, 8,9 Go de RAM, connexion par partage 4G (lente).
Méthode : `k3s-uninstall.sh`, puis **uniquement** la section *Reproduce* du README (étapes 1 à 9).

## Déroulement

Durées relevées dans le journal brut ci-dessous (horodatage `===`). Total : 55 minutes, de l'étape 1 (13:12:58) à la mesure (14:07:38), plus 4 minutes de désinstallation et de redémarrage avant.

| Étape README | Contenu | Durée | Résultat |
|---|---|---|---|
| 1 | audit et chiffrement (drop-ins avant k3s) | < 1 min | OK |
| 2 | k3s v1.36.5, import des images préchargées | 21 min | OK au 2e contrôle (13:25), voir la note |
| 3 | Cilium 1.20.4 + Hubble | 2 min | OK |
| 4 | namespaces, `db-creds` initial, application, RBAC | 3 min | OK, pods et DNS vérifiés |
| 5 | Vault : init, unseal, configuration | 13 min | OK après relance (voir trou 1) |
| 5 | ESO 2.14.0 + SecretStore + ExternalSecret | 5 min | OK, `SecretSynced` |
| 5 | Falco 0.45.2 + Falcosidekick | 3 min | OK |
| 6 | NetworkPolicies | < 1 min | OK |
| 7 | Kyverno + `kyverno test` | 5 min (dont l'installation du CLI) | OK, 6/6 après installation du CLI (voir trou 2) |
| 8 | `harden-serviceaccounts.sh` | 1 min | OK, tous les pods Running |
| 9 | `measure.sh rebuild` | < 1 min | identique aux mesures d'intégration |

Note sur l'étape 2 : au premier contrôle (13:17), `secrets-encrypt status` échouait encore et 17 images sur 27 étaient chargées ; au second (13:25), le nœud était `Ready`, le chiffrement `Enabled` et les 27 images chargées. Le contrôle de l'étape 3 a commencé à 13:34. La durée de l'étape 5 (Vault) vient du téléchargement de l'image Vault sur la 4G, pas de la configuration elle-même.

## Critères de réussite

| # | Critère | Résultat |
|---|---|---|
| 1 | Nœud `Ready`, Cilium `OK` | OK |
| 2 | `kyverno test admission/tests/` | 6 réussis, 0 échec |
| 3 | R1 (initContainer) refusé, R10 (modification de `db-creds`) refusée | OK |
| 4 | ESO `SecretSynced`, ESO ne lit pas `kube-system` | OK (`no`) |
| 5 | Falco : contournement `echo docker-entrypoint` = 1 alerte, redémarrage frontend = 0 | OK |
| 6 | Mesures S1–S4 identiques à `docs/evidence/integration/results-zt-lab-b.md` | IDENTIQUE |

Détail : [`criteres-zt-lab-b.txt`](criteres-zt-lab-b.txt) et [`results-zt-lab-b.md`](results-zt-lab-b.md).

## Trous trouvés dans le README et les scripts

- **Trou 1 (partie B, corrigé dans `b3451c7`)** : `secrets/vault-unseal.sh` n'attendait le pod Vault que 180 s. Sur une connexion lente, le téléchargement de l'image dépasse ce délai et le script s'arrête. Le délai passe à 600 s.
- **Trou 2 (partie A, corrigé dans `88b5e34`)** : l'étape 7 lance `kyverno test` sans dire d'installer le CLI Kyverno 1.19.2. Une VM neuve n'a pas non plus Helm ni le CLI Cilium : il faut une liste de prérequis au début de *Reproduce*.
- **Trou 3 (partie A, corrigé dans `88b5e34`)** : `k3s-uninstall.sh` laisse `/etc/cni/net.d`, donc le nœud passe `Ready` avant que Cilium soit installé. Il suffit d'ajouter `sudo rm -rf /etc/cni/net.d` après la désinstallation. Preuve (relecture A, B4) : `sudo stat /etc/cni/net.d` donne une création le 6 novembre 2026 à 18:00:49, donc **avant** la désinstallation du 8 novembre à 13:09 : le dossier a survécu à `k3s-uninstall.sh`. Le 8 novembre à 13:34:17, avant l'installation de Cilium (13:34:24), `ls` répondait « Permission non accordée » et non « Aucun fichier ou dossier », et le nœud était `Ready` dès 13:25. Le contenu du dossier à ce moment-là n'a pas été lu.
- **Trou 4 (partie A, proposition)** : à 13:17, la vérification de l'étape 2 a été lancée juste après le script d'installation de k3s. `kubectl get nodes` renvoyait « No resources found » (le nœud n'était pas encore enregistré), `k3s secrets-encrypt status` échouait (`secret-encrypt error ID 89848`) et seules 17 images sur 27 étaient importées. Au second contrôle (13:25), le nœud avait 8 min 7 s, il s'était donc enregistré vers 13:17:30 : k3s était encore en démarrage, pas en panne, et le chiffrement était bien `Enabled`. Proposition pour le README : attendre que le nœud soit **enregistré** avant les vérifications (`until kubectl get node "$(hostname)" >/dev/null 2>&1; do sleep 5; done`). Attendre `Ready` ne convient pas sur une machine propre, car le nœud ne devient `Ready` qu'après l'installation de Cilium (étape 3).
- **Écart avec zt-lab-a** : au critère 3a, zt-lab-b refuse aussi le pod via `disallow-latest-tag`, une politique qui n'apparaît pas dans `criteres-zt-lab-a.txt`. Vérifié par A : la politique est en `Enforce` sur zt-lab-a aussi, la capture initiale était tronquée (note datée dans `criteres-zt-lab-a.txt`).

## Écart déclaré par rapport au README

Pour économiser la bande passante, les images déjà téléchargées ont été exportées avant la désinstallation, dans `/var/tmp/zt-images` (27 archives), puis préchargées dans `/var/lib/rancher/k3s/agent/images/` (mécanisme air-gap de k3s). Seule l'image Vault n'a pas pu être exportée : elle a été retéléchargée. Ce préchargement ne change ni les versions ni la configuration, seulement le temps de téléchargement.

## Journal brut (horodaté)

```
=== 13:09:22 DÉBUT reconstruction zt-lab-b, commit 89e2faa, images exportées : 27 fichiers 1,5 Go (Vault non exportable)
=== 13:09:22 Désinstallation k3s
+ [ -d /etc/yum.repos.d ]
+ remove_uninstall
+ rm -f /usr/local/bin/k3s-uninstall.sh
=== 13:09:43 Redémarrage
=== 13:12:28 Après redémarrage
=== 13:12:58 README étape 1 : audit et chiffrement (drop-ins avant k3s)
=== 13:13:05 AJOUT HORS README (connexion lente) : images pré-chargées via le dossier air-gap de k3s
27
=== 13:13:16 README étape 2 : k3s v1.36.5
[INFO]  systemd: Enabling k3s unit
Created symlink /etc/systemd/system/multi-user.target.wants/k3s.service → /etc/systemd/system/k3s.service.
[INFO]  systemd: Starting k3s
=== 13:17:19 Vérifications étape 2
k3s version v1.36.5+k3s1 (3dd98cc5)
No resources found
time="2026-11-08T13:17:20+01:00" level=fatal msg="Error: see server log for details: Internal error occurred: secret-encrypt error ID 89848"
-rw------- 1 root root 1359986 nov.   8 13:17 /var/lib/rancher/k3s/server/logs/audit.log
images chargées : 17
=== 13:25:40 Vérifications étape 2 (2e essai)
NAME       STATUS   ROLES           AGE    VERSION
zt-lab-b   Ready    control-plane   8m7s   v1.36.5+k3s1
Encryption Status: Enabled
Current Rotation Stage: start
Server Encryption Hashes: All hashes match

Active  Key Type  Name
------  --------  ----
 *      AES-CBC   aescbckey

images chargées : 27
=== 13:34:17 Remarque : configuration CNI restée après k3s-uninstall
ls: impossible d'ouvrir le répertoire '/etc/cni/net.d/': Permission non accordée
=== 13:34:24 README étape 3 : Cilium 1.20.4
ℹ️  Using Cilium version 1.20.4
ℹ️  Using cluster name "default"
🔮 Auto-detected kube-proxy has not been installed
ℹ️  Cilium will fully replace all functionalities of kube-proxy
[32m \__[34m/¯¯\[35m__/[0m    Hubble Relay:       [32mOK[0m
[34m[34m[34m    \__/[0m       ClusterMesh:        [36mdisabled[0m

DaemonSet              cilium                   Desired: 1, Ready: [32m1/1[0m, Available: [32m1/1[0m
DaemonSet              cilium-envoy             Desired: 1, Ready: [32m1/1[0m, Available: [32m1/1[0m
Deployment             cilium-operator          Desired: 1, Ready: [32m1/1[0m, Available: [32m1/1[0m
Deployment             hubble-relay             Desired: 1, Ready: [32m1/1[0m, Available: [32m1/1[0m
Deployment             hubble-ui                Desired: 1, Ready: [32m1/1[0m, Available: [32m1/1[0m
Containers:            cilium                   Running: [32m1[0m
                       cilium-envoy             Running: [32m1[0m
                       cilium-operator          Running: [32m1[0m
                       clustermesh-apiserver    
                       hubble-relay             Running: [32m1[0m
                       hubble-ui                Running: [32m1[0m
Cluster Pods:          5/5 managed by Cilium
Helm chart version:    1.20.4
Image versions         cilium             quay.io/cilium/cilium:v1.20.4@sha256:20fe92e4c86641233a450098c158d2d29085f3419931ab6bf681d2485dedf16e: 1
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.39.5-1792733054-8c73b2816bc8239e27f1fd53b271884688137459@sha256:547ab45f6092f681d9f54f3be9fa8fb1e705c9c5dc2df388efe3a52aa6965629: 1
                       cilium-operator    quay.io/cilium/operator-generic:v1.20.4@sha256:7a7a3489dc66ad67e420d285c8a8d2e169b0957ad15e120f593d27081bf38d82: 1
                       hubble-relay       quay.io/cilium/hubble-relay:v1.20.4@sha256:cb23408209697ed30d2bc462e1f01eb622ea4423a891458f78bc88d7255bbfc1: 1
                       hubble-ui          quay.io/cilium/hubble-ui-backend:v0.13.6@sha256:83b3fc763f3d49948c306bf49b08277383e195904b9ca5c0c0022b2112628787: 1
                       hubble-ui          quay.io/cilium/hubble-ui:v0.13.6@sha256:049a80a03585c043d0c3121bdc518c72b0fd42bae07e4bcce0fdb8f1e88041d0: 1
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   cilium-envoy-rvc4s                        1/1     Running   0          87s
kube-system   cilium-hbhgp                              1/1     Running   0          87s
kube-system   cilium-operator-55b88cf477-ccn7l          1/1     Running   0          87s
kube-system   coredns-7cfb7bc9c7-zsdnb                  1/1     Running   0          19m
kube-system   hubble-relay-7b9cc7bdd5-2nm89             1/1     Running   0          87s
kube-system   hubble-ui-865d8bd5cf-wxgsl                2/2     Running   0          87s
kube-system   local-path-provisioner-77b9867795-6qzbp   1/1     Running   0          19m
kube-system   metrics-server-6dc596dfb8-pbvr6           1/1     Running   0          19m
=== 13:36:38 README étape 4 : namespaces, db-creds, app, rbac
namespace/zt-frontend created
namespace/zt-api created
namespace/zt-data created
namespace/zt-attacker created
secret/db-creds created
namespace/zt-frontend unchanged
namespace/zt-api unchanged
namespace/zt-data unchanged
namespace/zt-attacker unchanged
serviceaccount/sa-frontend created
configmap/frontend-nginx created
deployment.apps/frontend created
service/frontend created
serviceaccount/sa-api created
deployment.apps/api created
service/api created
serviceaccount/sa-database created
persistentvolumeclaim/db-data created
deployment.apps/database created
service/database created
serviceaccount/sa-attacker created
pod/attacker created
serviceaccount/eso-vault created
=== 13:37:11 Vérifications étape 4 (pods + DNS)
zt-api        api-7bf489ffd-8j8bt                       1/1     Running   0          31s
zt-attacker   attacker                                  1/1     Running   0          30s
zt-data       database-7b5846d867-7xbrp                 1/1     Running   0          30s
zt-frontend   frontend-56f75b99bc-jln2q                 1/1     Running   0          31s
Address: 10.43.69.199

=== 13:39:27 Fichier reproduce étape 2 : Vault
NAME: vault
LAST DEPLOYED: Sun Nov  8 13:39:40 2026
NAMESPACE: vault
STATUS: deployed
REVISION: 1
NOTES:
error: timed out waiting for the condition on pods/vault-0
== 1. Journal d'audit Vault (volume /vault/audit)
error: unable to upgrade connection: container not found ("vault")
-rw------- 1 doha doha 185 nov.   6 19:20 /home/doha/vault-init.json
=== 13:49:45 TROU (partie B) : vault-unseal.sh attend 180 s, insuffisant pendant le téléchargement de l'image Vault
pod/vault-0 condition met
== Initialisation de Vault (1 clé, seuil 1 : acceptable en lab uniquement)
Clés écrites dans /home/doha/vault-init.json (ne JAMAIS commit ce fichier)
== Descellement
{
  "sealed": false,
  "progress": 0
}
{
  "initialized": true,
  "sealed": false,
  "version": "2.0.4",
  "storage_type": "raft"
}
====== Version 1 ======
Key              Value
---              -----
created_by       {"actor":"root","client_id":"0DHqvq2D77kL2/JTPSZkTMJbkFVmUu0TzMi0jiXcFy8=","operation":"create"}
created_time     2026-11-08T12:51:11.683681627Z
deleted_by       <nil>
deletion_time    n/a
destroyed        false
Key                                         Value
---                                         -----
alias_metadata                              map[]
alias_name_source                           serviceaccount_uid
audience                                    vault
bound_service_account_names                 [eso-vault]
bound_service_account_namespace_selector    n/a
bound_service_account_namespaces            [zt-data]
token_bound_cidrs                           []
token_explicit_max_ttl                      0s
token_max_ttl                               30m
token_no_default_policy                     false
token_num_uses                              0
token_period                                0s
token_policies                              [zt-database-read]
token_ttl                                   15m
token_type                                  default
-rw------- 1 doha doha 185 nov.   8 13:51 /home/doha/vault-init.json
=== 13:52:19 Fichier reproduce étape 3 : ESO (scopedRBAC)
NAME: external-secrets
LAST DEPLOYED: Sun Nov  8 13:54:28 2026
NAMESPACE: external-secrets
STATUS: deployed
REVISION: 1
TEST SUITE: None
NAME    AGE   STATUS   CAPABILITIES   READY
vault   5s    Valid    ReadWrite      True
NAME       STORETYPE     STORE   REFRESH INTERVAL   STATUS         READY   LAST SYNC
db-creds   SecretStore   vault   1m                 SecretSynced   True    10s
ESO lit kube-system : no
=== 13:57:18 Fichier reproduce étape 4 : Falco
Image is up to date for sha256:866076a50b73513a8cd8a7c405e818af1a558be4fd95eaf1526090db1d0bfefb
Image is up to date for sha256:071a442c9a11e770b43ee879d9c12d8a3730382487585b8adb2c9bd0a9889eb0
Image is up to date for sha256:520fd427ab0fb62a8508015b7b4f50573ffc10a7b43f4757d67540e36f36a546
Image is up to date for sha256:5201d82d1c6cd9a13c9b625a3cf2dd8224739d5ef4e7593629ad4f2e70885d37
Image is up to date for sha256:2d62a53dfab6f3355f6283dc1f8fa292d04eb6c6f7665d53f44bc213a5ef4cd3
NAME: falco
LAST DEPLOYED: Sun Nov  8 13:58:21 2026
NAMESPACE: falco
STATUS: deployed
REVISION: 1
NOTES:
Sun Nov 08 12:59:17 2026: [libs]: container: * enabled container runtime socket at '/host/run/k3s/containerd/containerd.sock'
NAME                                      READY   STATUS    RESTARTS   AGE
falco-falcosidekick-698768f6cf-pj5l4      1/1     Running   0          63s
falco-falcosidekick-ui-5fdb49bc89-s8dtt   1/1     Running   0          63s
falco-falcosidekick-ui-redis-0            1/1     Running   0          63s
falco-p5xf2                               2/2     Running   0          63s
=== 14:00:42 README étape 6 : NetworkPolicy
networkpolicy.networking.k8s.io/allow-ui-to-redis-egress created
networkpolicy.networking.k8s.io/allow-ui-to-redis-ingress created
ciliumnetworkpolicy.cilium.io/allow-dns-egress created
ciliumnetworkpolicy.cilium.io/allow-falco-rules-download created
NAME       STORETYPE     STORE   REFRESH INTERVAL   STATUS         READY   LAST SYNC
db-creds   SecretStore   vault   1m                 SecretSynced   True    11s
=== 14:00:55 README étape 7 : Kyverno 3.9.2 + admission
NAME: kyverno
LAST DEPLOYED: Sun Nov  8 14:01:07 2026
NAMESPACE: kyverno
STATUS: deployed
REVISION: 1
NOTES:
clusterpolicy.kyverno.io/best-practices-disallow-latest-tag created
clusterpolicy.kyverno.io/best-practices-require-limits created
clusterpolicy.kyverno.io/supply-chain-restrict-images created
clusterpolicy.kyverno.io/defaults-mutate-pod-defaults created
clusterrole.rbac.authorization.k8s.io/kyverno:background-controller:networkpolicies created
clusterpolicy.kyverno.io/defaults-generate-default-deny created
policyexception.kyverno.io/allow-latest-tag-for-test created
clusterpolicy.kyverno.io/secrets-only-from-eso created
NAME                                 ADMISSION   BACKGROUND   READY   AGE   MESSAGE
best-practices-disallow-latest-tag   true        true         True    1s    Ready
best-practices-require-limits        true        true         True    1s    Ready
defaults-generate-default-deny       true        true         True    0s    Ready
defaults-mutate-pod-defaults         true        true         True    1s    Ready
secrets-only-from-eso                true        false        True    0s    Ready
supply-chain-restrict-images         true        true         True    1s    Ready
kyverno : commande introuvable
=== 14:02:31 TROU (partie A) : README étape 7 utilise 'kyverno test' sans dire d'installer le CLI Kyverno (ni Helm ni le CLI Cilium, absents d'une VM neuve)
Version: 1.19.2
Time: 2026-10-20T22:13:49Z
=== 14:03:57 README étape 7 (suite) : kyverno test
│ 6  │ best-practices-require-limits      │ require-cpu-memory-limits │ v1/Pod/zt-attacker/bad-init-pod │ Pass   │ Ok     │
│────│────────────────────────────────────│───────────────────────────│─────────────────────────────────│────────│────────│


Test Summary: 6 tests passed and 0 tests failed

=== 14:06:06 README étape 8 : harden-serviceaccounts.sh
5.1.5  kube-public/default : automountServiceAccountToken=false
5.1.5  kyverno/default : automountServiceAccountToken=false
5.1.5  vault/default : automountServiceAccountToken=false
5.1.5  zt-api/default : automountServiceAccountToken=false
5.1.5  zt-attacker/default : automountServiceAccountToken=false
5.1.5  zt-data/default : automountServiceAccountToken=false
5.1.5  zt-frontend/default : automountServiceAccountToken=false
5.1.6  falco/falco : automountServiceAccountToken=false
5.1.6  falco/falco-falcosidekick : automountServiceAccountToken=false
5.1.6  falco/falco-falcosidekick-ui : automountServiceAccountToken=false
daemonset.apps/falco restarted
deployment.apps/falco-falcosidekick restarted
deployment.apps/falco-falcosidekick-ui restarted
pod "falco-falcosidekick-ui-redis-0" deleted from falco namespace
1.1.20 certificats /var/lib/rancher/k3s/server/tls/*.crt : 600
Waiting for daemon set "falco" rollout to finish: 0 out of 1 new pods have been updated...
Waiting for daemon set "falco" rollout to finish: 0 of 1 updated pods are available...
daemon set "falco" successfully rolled out
=== 14:07:25 README étape 9 : measure.sh rebuild
=== 14:07:38 Comparaison avec docs/evidence/integration/results-zt-lab-b.md
?? docs/evidence/rebuild/results-zt-lab-b.md
=== 14:08:16 Critère 6 : diff mesures rebuild vs intégration
IDENTIQUE
=== 14:23:26 Critère 5 : Falco contournement + redémarrage frontend
### 5. Falco
contournement 'echo docker-entrypoint' : alertes = 1  (attendu >= 1)
demarrage frontend (ns=zt-frontend) : alertes = 0  (attendu 0)
=== 14:27:17 Critère 1 : nœud + Cilium
NAME       STATUS   ROLES           AGE   VERSION
zt-lab-b   Ready    control-plane   69m   v1.36.5+k3s1
OK
```
