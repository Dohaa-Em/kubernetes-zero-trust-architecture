# Reconstruction depuis zéro, zt-lab-a (Abir Majdi)

Méthode : désinstallation complète (`k3s-uninstall.sh`, redémarrage), puis README seul, section Reproduce, ligne à ligne, le 8 novembre 2026 entre 00h13 et 01h00 (heure de la VM).
Résultat : cluster identique à l'original. Les 6 critères sont atteints (`criteres-zt-lab-a.txt`, `results-zt-lab-a.md` identique à `docs/evidence/integration/` hors libellé). Durée totale : 47 minutes.

## Étapes et durées
| Étape du README | Durée | Remarque |
| --- | --- | --- |
| 1 et 2 : audit, chiffrement, k3s v1.36.5 | 1 min | chiffrement `Enabled`, `audit.log` présent |
| 3 : Cilium 1.20.4 | 5 min | tout `OK`, 5 pods sur 5 gérés |
| 4 : namespaces, app, RBAC | 3 min | base bloquée tant que `db-creds` manque (trou n° 2) |
| 5 : Vault (init, unseal, configuration) | 3 min | rôle `eso` lié à `eso-vault` |
| 5 : ESO (scopedRBAC) | 2 min | `SecretSynced`, ne lit plus `kube-system` |
| 5 : Falco, Falcosidekick et interface | 7 min | 4 pods, socket k3s détecté |
| 6 : NetworkPolicy | 1 min | ESO toujours synchronisé, frontend→API ouvert, frontend→base bloqué |
| 7 : Kyverno 3.9.2 et admission | 8 min | première application refusée (trou n° 3) |
| 8 : durcissement des ServiceAccounts | 1 min | Falco relancé, de nouveau prêt en 1 min |
| 9 : mesures | 1 min | identique à l'original |

## Trous du README trouvés (corrigés dans le même commit)
1. **Accès au cluster** : le README disait `export KUBECONFIG=/etc/rancher/k3s/k3s.yaml`, mais ce fichier est en mode 0600 pour root (réglage de `cluster/k3s-config.yaml`) et l'ancien `~/.kube/config` pointe vers l'ancien cluster. Correction : copie vers `~/.kube/config`.
2. **Secret `db-creds` manquant** : la base lit ce Secret, aucun fichier du dépôt ne le crée, et `docs/reproduce-secrets-detection.md` renvoie au README pour cela. Sans lui, la base reste bloquée. Correction : création à la main avec un mot de passe aléatoire à l'étape 4 ; Vault le reprend à l'étape 5, puis ESO en devient propriétaire.
3. **Délai d'attente de Kyverno** : 180 secondes ne suffisent pas sur une connexion lente (images de 3 min 30 s et 1 min 19 s, plus les certificats). L'application de `admission/` échouait avec `no endpoints available`. Correction : délai de 10 minutes, avec un rappel de relancer `kubectl apply -f admission/`.

## À noter
- Le fichier de Doha (`docs/reproduce-secrets-detection.md`) a fonctionné tel quel pour Vault, ESO et Falco, sans aucun écart.
- Le premier lancement de `vault-unseal.sh` écrase `~/vault-init.json` : sauvegarder l'ancien avant de reconstruire.
