# kube-bench sur zt-lab-a : analyse

Outil : kube-bench v0.16.0, profil `k3s-cis-1.9`, lancé en root avec `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`.
Preuves : `kube-bench-zt-lab-a-before.txt` (avant corrections) et `kube-bench-zt-lab-a-after.txt` (après).

Note de méthode : le premier passage (`-before`) a été lancé sans kubeconfig sous sudo. Les contrôles qui appellent kubectl (famille 5.1) y échouaient pour cette raison, pas à cause du cluster. Pour ces contrôles, seul le fichier `-after` fait foi.

## Corrections appliquées
- 1.1.20 : 21 certificats de `/var/lib/rancher/k3s/server/tls` passés de 644 à 600.
- 5.1.5 : `automountServiceAccountToken: false` sur le ServiceAccount `default` des 13 namespaces.

Résultat final : 59 PASS, 4 FAIL, 53 WARN, 14 INFO.

## Les 4 FAIL restants
| Contrôle | Décision | Justification |
|---|---|---|
| 1.1.9 | Faux positif | Le fichier CNI est `/etc/cni/net.d/05-cilium.conflist`, en 600 root:root. kube-bench regarde un autre chemin. |
| 1.1.10 | Faux positif | Même fichier, propriétaire root:root. |
| 1.2.26 | Sans objet | k3s mono-nœud utilise SQLite (`state.db`), il n'y a pas d'etcd. Le chiffrement des Secrets au repos s'applique à cette base. |
| 5.1.6 | Accepté, justifié | Aucun pod des namespaces `zt-*` ne monte de jeton. Les pods concernés sont des composants qui appellent l'API : External Secrets, Falco, Cilium, CoreDNS, Hubble UI, Kyverno, Vault, local-path, metrics-server. Amélioration possible : désactiver le jeton pour Falcosidekick UI/Redis et Hubble UI via les valeurs des charts. |
