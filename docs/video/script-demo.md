# Script de la démonstration vidéo (#25)

Premier jet : passages **ESO** et **Falco** par Doha. Abir complète l'introduction, S1 à S4 et Kyverno.
Organisation : Abir tape les commandes sur **zt-lab-a** et enregistre ; Doha parle sur ses passages.
Les commandes sont à copier une par une, dans l'ordre. Le texte en face est ce qu'on dit pendant qu'elle s'exécute.

## Avant d'enregistrer (hors caméra)

```bash
cd ~/kubernetes-zero-trust-architecture && git pull --rebase
./secrets/vault-unseal.sh                       # si Vault est scellé (après un redémarrage)
kubectl get pods -A | grep -v -E 'Running|Completed'   # doit être vide
kubectl -n zt-data get externalsecret db-creds  # SecretSynced
# 2e terminal, laissé ouvert pendant tout l'enregistrement :
kubectl -n falco port-forward svc/falco-falcosidekick-ui 2802:2802
```

Ouvrir `http://localhost:2802` et **se connecter hors caméra** : les identifiants ne doivent jamais apparaître à l'écran.
Agrandir la police du terminal (au moins 16 pt) et vider l'écran (`clear`) entre deux passages.

## Passage ESO : le mot de passe vient de Vault et tourne sans intervention humaine (≈ 2 min 30)

| # | Commande (Abir) | Texte (Doha) |
| --- | --- | --- |
| 1 | `kubectl -n zt-data get externalsecret db-creds` | « Le mot de passe de la base n'est écrit nulle part dans Git ni à la main. Il vit dans Vault, et l'External Secrets Operator le recopie dans un Secret Kubernetes. Statut `SecretSynced` : la copie est à jour, vérifiée chaque minute. » |
| 2 | `kubectl -n zt-data get secret db-creds -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'` | « Ce Secret appartient à l'ExternalSecret : c'est ESO qui l'a créé, et une politique Kyverno empêche quiconque d'autre de le modifier, même l'administrateur. » |
| 3 | `kubectl auth can-i get secrets -n zt-data --as=system:serviceaccount:zt-frontend:sa-frontend` | « Et si le frontend est compromis ? Son compte n'a aucun droit sur les Secrets : `no`. Il n'a même pas de jeton monté. » |
| 4 | `./secrets/rotate-db-password.sh` | « Maintenant, une rotation complète. Le script change le mot de passe dans PostgreSQL, écrit la nouvelle version dans Vault, puis force ESO à resynchroniser. On n'affiche jamais le mot de passe, seulement son empreinte. » |
| 5 | *(lire la sortie du script)* | « L'empreinte avant et l'empreinte après sont différentes, et l'empreinte après est égale à la cible : le Secret Kubernetes a été mis à jour en quelques secondes. Le test de connexion confirme que la base accepte le nouveau mot de passe. » |
| 6 | `kubectl -n zt-data get externalsecret db-creds` | « `LAST SYNC` vient de changer. Limite assumée : le pod de la base garde l'ancien mot de passe en variable d'environnement jusqu'à son redémarrage. En production, on utiliserait des identifiants dynamiques de Vault. » |

Plan B si la rotation échoue (Vault scellé, réseau) : montrer `docs/evidence/secrets/` (sortie de rotation déjà enregistrée) et les captures de `docs/evidence/secrets/captures/`.

## Passage Falco : voir l'attaque, même quand elle est bloquée (≈ 2 min 30)

Garder l'interface Falcosidekick visible à côté du terminal : les alertes arrivent en quelques secondes.

| # | Commande (Abir) | Texte (Doha) |
| --- | --- | --- |
| 1 | `kubectl -n zt-frontend exec deploy/frontend -- sh -c 'id'` | « On joue l'attaquant qui a pris le frontend et ouvre un shell. Rien n'empêche ce shell, mais Falco le voit : alerte `ZT Shell spawned in app container`, niveau Warning, avec le namespace et le pod. » |
| 2 | `kubectl -n zt-data exec deploy/database -- sh -c 'nc -w 2 1.1.1.1 443; echo code=$?'` | « Plus grave : depuis la base, on tente de sortir vers Internet pour exfiltrer des données. La connexion échoue, car Cilium la bloque. Mais Falco lève quand même `ZT Outbound connection from data tier` : c'est la défense en profondeur, une couche bloque et une autre détecte. » |
| 3 | `kubectl -n vault exec vault-0 -- sh -c 'ls /vault/data'` | « Enfin, quelqu'un ouvre un shell dans Vault et regarde son stockage. Ce sont les deux alertes les plus graves de nos règles, niveau Critical : accès interactif à l'outil de secrets, et lecture du stockage Vault par un autre processus que Vault. » |
| 4 | `kubectl -n falco logs ds/falco -c falco --since=2m \| grep -o '"rule":"ZT[^"]*"' \| sort \| uniq -c` | « Les mêmes alertes, côté journal de Falco : nos cinq règles sont classées selon MITRE ATT&CK. Limite : Falco détecte mais ne bloque pas. Il faut quelqu'un, ou un outil de réponse, pour réagir. » |

Plan B si aucune alerte n'arrive : montrer `docs/evidence/detection/alerts-zt-lab-a.tsv` et les captures de `docs/evidence/detection/captures/`.

## À compléter par Abir

- Introduction : le problème et l'architecture (`docs/architecture/README.md`).
- Avant/après : S1 à S4 (`./scripts/measure.sh`), résultats identiques sur les deux VM.
- Kyverno : refus de R1 (initContainer) et de R10 (modification de `db-creds`).
- Conclusion : limites assumées et reconstruction 6/6 sur deux systèmes.
