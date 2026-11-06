# Flux réseau Vault et External Secrets Operator

Livré par B (secrets/) à A (network/), qui traduit chaque ligne en NetworkPolicy
ou CiliumNetworkPolicy (convention de nommage `<action>-<source>-to-<destination>`).

| # | Source (namespace / pod) | Destination | Port | Proto | Pourquoi | Type de règle |
| --- | --- | --- | --- | --- | --- | --- |
| V1 | `external-secrets` / contrôleur ESO (`app.kubernetes.io/name=external-secrets`) | `vault` / `vault-0` (`app.kubernetes.io/name=vault`) | 8200 | TCP | Login Kubernetes auth puis lecture de `secret/zt/database/*` | NetworkPolicy : egress côté ESO + ingress côté Vault |
| V2 | `external-secrets` / contrôleur ESO | kube-apiserver | 6443 | TCP | Surveiller les ExternalSecret, créer le Secret `db-creds`, demander un token (TokenRequest) pour `eso-vault` | CiliumNetworkPolicy `toEntities: [kube-apiserver]` |
| V3 | `external-secrets` / cert-controller | kube-apiserver | 6443 | TCP | Gérer les certificats du webhook ESO | CiliumNetworkPolicy `toEntities: [kube-apiserver]` |
| V4 | kube-apiserver | `external-secrets` / webhook ESO | 10250 | TCP | Validation des ressources ESO (webhook d'admission) | CiliumNetworkPolicy `fromEntities: [kube-apiserver]` |
| V5 | `vault` / `vault-0` | kube-apiserver | 6443 | TCP | TokenReview : vérifier le JWT présenté par ESO | CiliumNetworkPolicy `toEntities: [kube-apiserver]` |
| V6 | `vault`, `external-secrets` (tous les pods) | `kube-system` / CoreDNS | 53 | UDP/TCP | Résolution DNS | NetworkPolicy (même modèle que `allow-dns-egress`) |

Remarques :

- Avec un seul réplica, le port Raft 8201 n'est utilisé qu'en local : aucune règle.
- L'accès à l'interface Vault se fait par `kubectl port-forward` (non filtré par les NetworkPolicy, comme pour le frontend).
- Les pods applicatifs (`zt-*`) n'ont **aucun** flux vers Vault : ils lisent un Secret Kubernetes ordinaire. C'est l'un des intérêts d'ESO face à l'injection par sidecar.
- Le flux V2 vers l'API est le plus sensible : le contrôleur ESO peut écrire des Secrets dans tout le cluster (ClusterRole du chart). Le restreindre aux seuls namespaces utiles est une piste d'amélioration (`scopedNamespace` / `scopedRBAC` du chart).

Test après application (doit répondre `SecretSynced` et rester `Ready=True` après un `force-sync`) :

```bash
kubectl -n zt-data annotate externalsecret db-creds force-sync=$(date +%s) --overwrite
kubectl -n zt-data get externalsecret db-creds -w
```
