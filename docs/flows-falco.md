# Flux réseau Falco et Falcosidekick

Livré par B (detection/) à A (network/).

| # | Source (namespace / pod) | Destination | Port | Proto | Pourquoi | Type de règle |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | `falco` / DaemonSet falco (`app.kubernetes.io/name=falco`) | `falco` / falcosidekick (`app.kubernetes.io/name=falcosidekick`) | 2801 | TCP | Envoi des alertes en HTTP | NetworkPolicy egress + ingress |
| F2 | `falco` / falcosidekick | `falco` / falcosidekick-ui | 2802 | TCP | Transmission des alertes à l'interface web | NetworkPolicy egress + ingress |
| F3 | `falco` / falcosidekick-ui | `falco` / redis (falcosidekick-ui-redis) | 6379 | TCP | Stockage des alertes affichées | NetworkPolicy egress + ingress |
| F4 | `falco` / conteneur falcoctl (dans le pod falco) | Internet : `ghcr.io`, `pkg-containers.githubusercontent.com` | 443 | TCP | Téléchargement et mise à jour des règles officielles | CiliumNetworkPolicy `toFQDNs` (sinon : désactiver le suivi automatique des règles) |
| F5 | `falco` (tous les pods) | `kube-system` / CoreDNS | 53 | UDP/TCP | Résolution DNS | NetworkPolicy |
| F6 | `falco` / falcosidekick (optionnel) | URL du webhook de notification | 443 | TCP | Canal de notification externe | CiliumNetworkPolicy `toFQDNs` |

Remarques :

- Falco lit les évènements du noyau par eBPF et les métadonnées des conteneurs par le socket containerd monté depuis l'hôte (`/run/k3s/containerd/containerd.sock`). Ce n'est **pas** un flux réseau : les NetworkPolicy ne s'y appliquent pas. C'est la nouvelle surface d'attaque de Falco (pod privilégié avec accès noyau et runtime), à documenter comme exception justifiée.
- Falco n'a pas besoin de l'API Kubernetes dans cette configuration (le plugin k8smeta n'est pas activé).
- Le namespace `falco` ne doit pas être couvert par PSA `restricted` ni par les politiques Kyverno (elles ne ciblent que `zt-*`, c'est déjà le cas).
- Prudence avec F4 : sous un default deny, falcoctl échoue mais Falco continue avec les règles déjà chargées. Il suffit de le vérifier dans les logs, ce n'est pas bloquant.
