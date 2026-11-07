# kube-bench sur zt-lab-b

kube-bench 0.16.0, profil `k3s-cis-1.9` (le plus récent fourni ; écrit pour Kubernetes
1.27 à 1.29, aucun profil ne couvre encore k3s v1.36). Cibles : controlplane, etcd,
master, node, policies.

| | PASS | FAIL | WARN | INFO |
| --- | --- | --- | --- | --- |
| Avant (`results-zt-lab-b-before.*`) | 57 | 6 | 53 | 14 |
| Après (`results-zt-lab-b-after.*`) | 59 | 4 | 53 | 14 |

Les WARN sont surtout des contrôles manuels que kube-bench ne peut pas évaluer.

## Analyse des échecs

| Contrôle | Avant | Après | Analyse |
| --- | --- | --- | --- |
| 1.1.9, 1.1.10 Droits et propriétaire des fichiers CNI | FAIL | FAIL | **Faux positif.** Le contrôle lit `/var/lib/cni/networks` (IPAM host-local des CNI classiques). Cilium gère ses adresses lui-même et ne crée pas ce dossier : rien n'est trouvé, le contrôle échoue. |
| 1.1.20 Certificats PKI en 600 | FAIL | **PASS** | Corrigé : `chmod 600` sur `server/tls/*.crt` (`scripts/harden-serviceaccounts.sh`). Risque faible au départ, un certificat étant public. |
| 1.2.26 `--etcd-cafile` | FAIL | FAIL | **Non applicable.** k3s utilise ici SQLite (kine), pas etcd. |
| 5.1.5 ServiceAccounts `default` avec token automatique | FAIL | **PASS** | Corrigé : `automountServiceAccountToken: false` sur tous les SA `default` (hors kube-system, exclu par le contrôle). Aucun pod ne les utilisait. |
| 5.1.6 Tokens montés seulement si nécessaire | FAIL | FAIL | **Exception justifiée.** Les pods applicatifs (Abir, phase 2) et maintenant les 4 pods Falco n'ont plus de token. Restent ceux qui appellent l'API par fonction : ESO (écrit les Secrets, TokenRequest), Cilium (agent, Envoy, opérateur), CoreDNS, metrics-server, local-path-provisioner, Hubble UI, Vault (TokenReview, service_registration). |

Vérification après le retrait du token de Falco : alerte `ZT Shell` reçue avec namespace
et pod (métadonnées lues par le socket containerd), transmise à Falcosidekick (`POST OK`).
