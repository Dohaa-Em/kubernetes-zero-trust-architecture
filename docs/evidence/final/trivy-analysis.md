# Analyse Trivy (v0.76.2) des images de l'application sur zt-lab-b

Commande, pour chaque image, lue directement dans containerd sans la retélécharger :
`trivy image --image-src containerd --scanners vuln --severity HIGH,CRITICAL <image>`
(avec `CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock`, `CONTAINERD_NAMESPACE=k8s.io`).
Base de vulnérabilités du 8 novembre 2026. Preuves : `trivy-nginx-unprivileged.txt`, `trivy-podinfo.txt`, `trivy-postgres.txt`, `trivy-curl.txt`.
Périmètre : les 4 images de nos namespaces `zt-*`. Les images des composants tiers (Cilium, Vault, ESO, Kyverno, Falco) ne sont pas incluses.

## Résultats

| Image | Rôle | OS de base | HIGH | CRITICAL | Avec correctif |
| --- | --- | --- | --- | --- | --- |
| `nginxinc/nginx-unprivileged:1.27-alpine` | frontend (`zt-frontend`) | Alpine 3.21.3 | 62 | 3 | 65 / 65 |
| `ghcr.io/stefanprodan/podinfo:6.7.1` | API (`zt-api`) | Alpine 3.20.3 + 2 binaires Go | 101 | 6 | 107 / 107 |
| `postgres:16-alpine` | base de données (`zt-data`) | Alpine 3.24.4 | 25 | 1 | 26 / 26 |
| `curlimages/curl:8.10.1` | pod attaquant (`zt-attacker`, test uniquement) | Alpine 3.20.3 | 22 | 2 | 24 / 24 |

Pour podinfo, les résultats se répartissent ainsi : 23 dans l'OS Alpine, 44 dans le binaire `home/app/podinfo` et 40 dans `usr/local/bin/podcli`. Une même CVE peut apparaître dans les deux binaires Go.

## 1. Constat principal : des composants anciens, pas des failles sans solution

Toutes les vulnérabilités trouvées ont une version corrigée (colonne « Avec correctif »). La cause n'est pas la même selon l'image :

- **nginx-unprivileged, podinfo et curl** : l'OS de base est ancien (Alpine 3.20.3 ou 3.21.3), et pour podinfo les deux binaires Go sont compilés avec Go 1.23.2.
- **postgres** : l'OS est récent (Alpine 3.24.4) et n'a aucune faille HIGH ou CRITICAL. Les 26 résultats viennent tous d'un seul binaire Go embarqué, `usr/local/bin/gosu` (compilé avec la stdlib Go v1.24.6), que l'entrypoint utilise pour quitter root.

Ce n'est pas un défaut de configuration du cluster, c'est une **dette de mise à jour** des composants livrés dans les images.

## 2. Vulnérabilités CRITICAL

| CVE | Composant | Images | Version installée → corrigée | Commentaire |
| --- | --- | --- | --- | --- |
| CVE-2026-31789 | OpenSSL (`libcrypto3`, `libssl3`) | nginx, podinfo, curl | 3.3.2/3.3.3 → 3.3.7 | Trivy la décrit comme un dépassement de tas sur les systèmes **32 bits**. Notre nœud est en x86_64 : risque faible ici, mais à corriger. |
| CVE-2026-111497 | `brotli-libs` | nginx | 1.1.0 → 1.1.1 | Bibliothèque de compression utilisée par nginx. |
| CVE-2025-68121 | bibliothèque standard Go | podinfo, postgres | Go 1.23.2 / 1.24.6 → 1.24.13+ | Binaires Go compilés avec une version de Go ancienne. Dans postgres, c'est le binaire `gosu` embarqué dans l'image, pas PostgreSQL lui-même. |
| CVE-2026-33186 | `google.golang.org/grpc` | podinfo | 1.67.1 → 1.79.3 | Dépendance de podinfo. |

## 3. Ce que l'architecture Zero Trust limite déjà

Ces failles restent présentes dans les images. En revanche, les contrôles du projet réduisent ce qu'un attaquant peut en faire, une fois une faille exploitée :

- **Admission (PSA `restricted` + Kyverno)** : les conteneurs tournent sans root, sans escalade de privilèges, sans capacités Linux, avec seccomp et un système de fichiers en lecture seule (Kubescape C-0013, C-0016 et C-0017 sans échec sur `zt-*`). Kyverno n'accepte que les images de la liste autorisée.
- **Réseau (default deny + Cilium)** : un frontend compromis ne joint que l'API, jamais la base, l'API Kubernetes ou Internet (mesures S1). L'exploitation d'une faille réseau est donc limitée aux flux explicitement autorisés.
- **Secrets (Vault + ESO)** : aucun jeton de ServiceAccount n'est monté par défaut, et le mot de passe de la base n'est pas lisible depuis un pod compromis (mesures S2 et S4).
- **Détection (Falco)** : les comportements typiques d'une exploitation (shell, lecture de jeton, connexion sortante de la base) déclenchent une alerte.

## 4. Décision

- **Acceptées pour le laboratoire** : on ne change pas les versions à quelques jours de la remise. Cela invaliderait les mesures, la reconstruction et la liste d'images autorisées par Kyverno, qui ont été validées avec ces tags.
- **Recommandations pour une mise en production** :
  1. Mettre à jour les tags vers les dernières versions corrigées, puis épingler les images par digest (`@sha256:…`) dans les manifestes et dans la politique Kyverno.
  2. Ajouter Trivy à la CI, par exemple `trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed`, pour bloquer une image avec une faille critique corrigeable.
  3. Rescanner régulièrement : une image saine aujourd'hui peut ne plus l'être dans un mois, comme le montre ce scan.
  4. Pour l'API, retirer `podcli` de l'image (outil en ligne de commande inutile en production, qui représente 40 des 107 résultats) ou passer à une image minimale (distroless).

## 5. Limites

- Seules les sévérités HIGH et CRITICAL sont listées. Les MEDIUM et LOW ne sont pas analysées.
- Le scan détecte des versions vulnérables, il ne prouve pas qu'une faille est exploitable dans notre configuration.
- Les images des composants tiers ne sont pas scannées : elles relèvent de leurs éditeurs et de leurs propres mises à jour.
