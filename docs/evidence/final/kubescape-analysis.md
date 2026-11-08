# Analyse Kubescape (v4.0.20, cadres NSA et MITRE) sur zt-lab-a

Commande : `kubescape scan framework nsa,mitre --exclude-namespaces kube-system,kube-public,kube-node-lease`.
Preuves : `kubescape-zt-lab-a-before.txt` (avant) et `kubescape-zt-lab-a-after.txt` (après correction).
Couverture : 38 contrôles sur 40. C-0069 et C-0070 exigent l'opérateur Kubescape (KubeletInfo), pas le CLI : non évalués, hors périmètre.

## Scores
| Cadre | Avant | Après |
| --- | --- | --- |
| NSA | 68,07 | 68,75 |
| MITRE | 65,11 | 65,11 |

Le score est global à tout le cluster : il est tiré vers le bas par les composants tiers (voir plus bas). Sur nos namespaces `zt-*`, le résultat est passé d'un seul contrôle en échec à zéro. Preuve : `kubescape-zt-lab-a-resources.tsv` (scan du 8 novembre 2026, aucune ressource `zt-*` en échec ; un seul compte d'ESO est lié à `zt-data`, voir § 3).

## 1. Vrai défaut sur nos ressources, corrigé
- **C-0013 (conteneurs non-root)** sur `zt-frontend/frontend`, `zt-api/api` et `zt-attacker/attacker`. Cause : `runAsGroup` absent (`runAsNonRoot` et `runAsUser` étaient définis, la base de données avait déjà `runAsGroup`). Correction : `runAsGroup` ajouté dans `app/10-frontend.yaml`, `app/20-api.yaml`, `app/40-attacker.yaml`. Après redéploiement : aucun échec sur `zt-*`.
- Les autres contrôles liés à nos pods (C-0016 escalade de privilèges, C-0017 système de fichiers modifiable, C-0034 jeton automatique, C-0030 réseau) ne signalent rien sur `zt-*`.

## 2. Faux positifs
- **C-0036 et C-0039 (validating / mutating admission controller)** : Kubescape signale les webhooks de Kyverno comme un risque. Ce sont justement nos contrôles d'admission, voulus.

## 3. Composants tiers : détail des ressources en échec (scan du 8 novembre 2026)
Le scan JSON (`kubescape scan framework nsa,mitre --exclude-namespaces kube-system,kube-public,kube-node-lease --format json`) compte **46 identifiants de ressources en échec** et 98 réussis. Ils correspondent à **37 objets**, car un ServiceAccount apparaît une fois par Role lié (16 identifiants pour 7 comptes). Le scan précédent comptait 47 ressources. Liste complète (ressource, contrôle) : `kubescape-zt-lab-a-resources.tsv`.

| Composant | Objets | Détail |
| --- | --- | --- |
| Kyverno | 19 | 4 déploiements, 10 webhooks, 4 ServiceAccounts, le namespace `kyverno` |
| External Secrets Operator | 7 | 3 déploiements, 2 webhooks, 2 ServiceAccounts |
| Falco | 4 | `falco`, `falco-falcosidekick`, `falco-falcosidekick-ui`, `falco-falcosidekick-ui-redis` |
| Vault | 2 | le StatefulSet et son ServiceAccount |
| Namespaces `default` et `cilium-secrets` | 2 | pas de default-deny (C-0030) |
| Sujets RBAC de k3s | 3 | groupe `system:masters`, utilisateurs `system:kube-controller-manager` et `system:kube-scheduler` |
| **Total** | **37** | |

**Aucune charge de travail de nos namespaces `zt-frontend`, `zt-api`, `zt-data` et `zt-attacker` n'est en échec**, y compris pour C-0013 : les 7 ressources encore en échec sont toutes des composants tiers. Un seul identifiant brut contient `zt-data` : le ServiceAccount `external-secrets` (namespace `external-secrets`), lié par le Role `external-secrets-controller` à `zt-data`. Il échoue sur C-0007 (suppression), C-0015 (lecture des Secrets) et C-0053 (accès au jeton), ce qui correspond à son rôle : ESO limité à `zt-data` doit y lire et y écrire les Secrets (relecture A1, `docs/evidence/secrets-policy/eso-scoped-rbac-zt-lab-a.txt`).

Les échecs viennent des charts installés, pas de notre configuration. Contrôles concernés : C-0270 et C-0271 (limites CPU et mémoire), C-0015, C-0007 et C-0035 (droits RBAC de lecture des Secrets, de suppression, rôles d'administration), C-0053 et C-0034 (jetons de ServiceAccount, nécessaires aux contrôleurs), C-0057, C-0045 et C-0048 (privilégié et hostPath, attendus pour le pilote eBPF de Falco), C-0030 (namespaces `default`, `kyverno`, `cilium-secrets` sans politique réseau).
Décision : acceptés, ces composants ont besoin de ces droits pour fonctionner. Ils sont documentés comme surface de risque (voir aussi la relecture A1 : droits d'ESO sur tous les Secrets).

## 4. Limites
- Les namespaces `default` et `kyverno` n'ont pas de default-deny : pistes d'amélioration, hors périmètre des zones Zero Trust `zt-*`.
- C-0069 et C-0070 non évalués (opérateur requis).

## 5. Contrôles que Kubescape ne peut pas vérifier sur k3s
Trois contrôles restent en « Action Required » parce que le CLI ne sait pas les évaluer sur k3s (avec C-0069 et C-0070, cela fait les 5 du scan). Le projet les couvre autrement :
- **Chiffrement des Secrets (etcd)** : vérifié par lecture directe du datastore, marqueur lisible 1 avant et 0 après, AES-CBC (`docs/evidence/etcd-encryption/`).
- **Journaux d'audit activés** : vérifiés par l'audit lui-même, `exec` tracé, accès refusé en code 403, 0 occurrence du mot de passe (`docs/evidence/audit/`).
- **PSP (Pod Security Policy)** : supprimé de Kubernetes depuis la version 1.25 et remplacé par Pod Security Admission, en niveau `restricted` sur nos namespaces (rapport, section 4.4).
