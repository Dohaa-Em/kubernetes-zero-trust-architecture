# Relecture croisée : B (Doha) relit le travail de A (Abir)

Phase 7, guide §7.2 étape 6. Périmètre : `rbac/`, `network/`, `admission/`, `README.md`
et les sections 4.2 à 4.4 du rapport. Relu le 7 novembre 2026 sur le commit `273b6ea` ;
tests sur `zt-lab-b` avec toutes les couches actives.

## Points forts

- Default deny ingress **et** egress dans chaque namespace applicatif, DNS explicite, un flux par chemin légitime, sélecteurs sur `kubernetes.io/metadata.name` (étiquette non modifiable). Résultat S1 identique sur les deux clusters.
- Zéro permission Kubernetes pour les workloads, aucun token monté, et 8 contrôles de permissions dangereuses (7 droits nommés plus « tous les verbes sur toutes les ressources ») vérifiés pour les 5 comptes (`docs/evidence/rbac/dangerous-permissions-zt-lab-a.txt`). Le choix « aucune Role » est justifié dans le rapport (4.2).
- Analyse fail-open / fail-closed de Kyverno mesurée (`docs/evidence/fail-mode/analysis.md`), y compris la tentative écartée et pourquoi.
- Politiques ESO (`70`) et NetworkPolicy des outils (`40`, `50`) vérifiées aussi sur `zt-lab-b` (`85ec20c`).

## Remarques

| # | Gravité | Fichier | Constat | Proposition |
| --- | --- | --- | --- | --- |
| R1 | **Haute** | `admission/10`, `20`, `30` | Les motifs ne vérifient que `spec.containers`. Une image hors liste, en tag `latest` et sans limites passe les trois politiques si elle est placée dans un `initContainer`. **Confirmé** (preuve ci-dessous). Même risque pour `ephemeralContainers`. | Ajouter `=(initContainers)` et `=(ephemeralContainers)` aux trois motifs (exemple ci-dessous), puis ajouter le cas aux tests CLI `admission/tests/`. |
| R2 | Moyenne | `README.md` | La section « Reproduce » ne permet pas de reconstruire le lab : k3s non épinglé (`INSTALL_K3S_CHANNEL=stable` au lieu de v1.36.5), options Cilium absentes, aucune étape Vault, ESO, Falco, audit, chiffrement etcd, `scripts/harden-serviceaccounts.sh`, et options Kyverno manquantes (voir R3). Bloquant pour le ticket #24 (reconstruction par l'autre personne avec le README seul). | Une liste ordonnée suivant le guide §7.3, avec les versions de `versions.md`. B peut écrire la partie secrets/détection. |
| R3 | Moyenne | installation de Kyverno | **Étape manuelle non documentée** révélée par l'intégration : le chart 3.9.2 désactive les PolicyException. Sans `--set features.policyExceptions.enabled=true --set features.policyExceptions.namespace=kyverno`, `admission/60-policy-exception.yaml` est créé mais sans effet. | Écrire la commande `helm install kyverno` complète dans le README ou `versions.md`. |
| R4 | Moyenne | `network/00` + `app/10` | Aucune règle n'autorise l'entrée vers le frontend : il n'est joignable que par `kubectl port-forward`, qui passe par le kubelet et n'est pas filtré par les NetworkPolicy. La frontière « Internet → frontend » du modèle de menaces n'est donc pas réellement exercée. | Soit l'écrire comme limite du lab, soit ajouter une règle d'entrée depuis un contrôleur d'Ingress ou un NodePort, et rejouer S1 depuis l'extérieur. |
| R5 | Moyenne | PSA et Kyverno | Les contrôles d'admission ne couvrent que `zt-*`. Un pod privilégié créé dans `default` ou dans un nouveau namespace hors `zt-*` n'est refusé par rien. Aucun ServiceAccount applicatif n'a le droit de créer des pods, donc le risque vise surtout une erreur d'opérateur. | Niveau PSA `baseline` par défaut pour tout le cluster (AdmissionConfiguration de k3s) avec exemptions explicites (`kube-system`, `falco`), ou au minimum le citer dans les limites. |
| R6 | Basse | `network/00` | `allow-dns-egress` autorise n'importe quelle requête vers CoreDNS, qui résout aussi les noms externes : un pod compromis peut exfiltrer par tunnel DNS. | Citer en risque résiduel ; une règle DNS Cilium (`rules.dns: matchPattern "*.cluster.local"`) le réduirait. |
| R7 | Basse | `admission/30` | Liste blanche par tag, pas par empreinte : `postgres:*` accepte tout le dépôt Docker Hub `postgres`, et un tag peut être réécrit par son éditeur. La vérification de signature cosign du plan n'est pas faite. | Épingler les images par `@sha256` ou citer en piste d'amélioration avec `verifyImages`. |
| R8 | Info | `admission/40` | La mutation `+(automountServiceAccountToken): false` n'agit que si le champ est absent : un pod qui écrit `true` garde son token (vu avec `detection/tests/token-reader-pod.yaml`). C'est voulu pour un défaut, mais ce n'est pas un contrôle. | Le préciser dans le rapport, ou ajouter une règle `validate`. |
| R9 | Info | `admission/50` | Le ClusterRole donne au contrôleur d'arrière-plan de Kyverno le droit de créer et **supprimer** des NetworkPolicy dans tout le cluster : compromettre Kyverno permet d'effacer le default deny. | À ajouter à la surface d'attaque de Kyverno (rapport, section 10). |

## Preuve de R1

Test sans création réelle (`kubectl apply --dry-run=server`), `zt-lab-b`, 7 novembre 2026,
manifeste `docs/evidence/review/initcontainer-bypass.yaml` :

```text
=== Test 1 : image interdite dans un initContainer
pod/bypass-test created (server dry run)
=== Test témoin : la même image dans un conteneur normal (doit être refusée)
best-practices-disallow-latest-tag:
  validate-image-tag: 'validation error: Using the ''latest'' tag is not allowed. rule validate-image-tag failed at path /spec/containers/0/image/'
supply-chain-restrict-images:
  allowed-images-only: 'validation error: Image not in the project allowlist. rule allowed-images-only failed at path /spec/containers/0/image/'
```

Pod Security `restricted` n'arrête pas ce pod : son `initContainer` respecte le contexte de
sécurité demandé. Seules les règles Kyverno devaient l'arrêter.

## Correction proposée pour R1

Même principe pour les trois politiques : `=(…)` signifie « si le champ existe, il doit
respecter le motif ». Exemple pour `30-restrict-images.yaml` :

```yaml
        pattern:
          spec:
            =(initContainers):
              - image: "ghcr.io/stefanprodan/* | nginxinc/nginx-unprivileged:* | postgres:* | curlimages/curl:*"
            =(ephemeralContainers):
              - image: "ghcr.io/stefanprodan/* | nginxinc/nginx-unprivileged:* | postgres:* | curlimages/curl:*"
            containers:
              - image: "ghcr.io/stefanprodan/* | nginxinc/nginx-unprivileged:* | postgres:* | curlimages/curl:*"
```

Pour `20-require-limits.yaml`, ajouter le même bloc `resources.limits` sous
`=(initContainers)`. Les conteneurs éphémères n'acceptent pas de limites de ressources
dans Kubernetes : ne pas les ajouter à cette politique-là.

Validation après correction : relancer le test 1, qui doit être **refusé**, puis
`kyverno test admission/tests/` avec un cas `initContainer` ajouté.

## Complément du 7 novembre au soir : R10

| # | Gravité | Fichier | Constat | Proposition |
| --- | --- | --- | --- | --- |
| R10 | **Haute** | `admission/70-secrets-only-from-eso.yaml` | La politique ne bloque que la **création**. Toute **modification** d'un Secret de `zt-data` par un autre compte qu'ESO est acceptée : `kubectl annotate secret db-creds` par l'administrateur a réussi (`docs/evidence/secrets-policy/results-zt-lab-b.txt`, test 2). Cause : depuis Kyverno 1.13, `allowExistingViolations` vaut `true` par défaut. Sur un UPDATE, Kyverno évalue aussi l'ancien objet et laisse passer s'il violait déjà la règle. Or cette règle ne dépend que de l'utilisateur de la requête, donc l'ancien objet « viole » toujours. | Ajouter `allowExistingViolations: false` sous `failureAction: Enforce`. **Testé sur zt-lab-b** : la modification par l'administrateur est refusée, la rotation par ESO passe toujours (`docs/evidence/review/secrets-policy-update-fix-zt-lab-b.txt`). |

Correction appliquée temporairement sur `zt-lab-b` (copie du fichier). Le fichier du dépôt
reste à modifier par A.
