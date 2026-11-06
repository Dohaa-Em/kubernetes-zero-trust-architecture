# Versions épinglées

Les deux membres installent exactement ces versions. Toujours donner la version à l'installation (par exemple `cilium install --version 1.20.4`, car le cilium-cli v0.20.2 installe sinon la 1.20.3). Pour Kyverno, `--version` prend la version du chart, pas celle de l'application.

## Versions communes aux deux clusters

| Outil | Version | Remarque |
| --- | --- | --- |
| k3s | v1.36.5+k3s1 | sans Flannel ni Traefik |
| Cilium | 1.20.4 | Hubble relay et UI inclus |
| cilium-cli | v0.20.2 | |
| Hubble CLI | v1.20.2 | |
| Helm | v3.22.1 | |
| Kyverno | chart 3.9.2 | application v1.19.2 |
| Kyverno CLI | 1.19.2 | tests dans `admission/tests` |
| Gitleaks | 8.30.1 | hook pre-commit |
| Falco | chart 9.2.2 | application 0.45.2, pilote modern_ebpf |
| Falcosidekick | 2.35.1 | interface 2.2.0, 1 réplica |
| Vault | chart 0.34.1 | application 2.0.4, Raft, 1 réplica |
| External Secrets Operator | chart 2.14.0 | API external-secrets.io/v1 |
| kube-bench | à renseigner (Doha) | |

## Machines

| Cluster | Responsable | Système | Noyau |
| --- | --- | --- | --- |
| zt-lab-a | Abir Majdi | Debian 13 | 6.12.111+deb13-amd64 |
| zt-lab-b | Doha El Merabet | Ubuntu 24.04 | 6.14.0-35-generic |

## Détail mesuré sur zt-lab-a (Abir Majdi)

| Composant | Version |
| --- | --- |
| git / gh | 2.47.3 / 2.46.0 |
| kubectl | v1.31.14 (à remplacer par `k3s kubectl`, voir ci-dessous) |
| Image podinfo (frontend, API) | ghcr.io/stefanprodan/podinfo:6.7.1 |
| Image base de données | postgres:16-alpine |
| Image nginx | nginxinc/nginx-unprivileged:1.27-alpine |
| Image de test | curlimages/curl:8.10.1 |
| Composants k3s par défaut | CoreDNS 1.14.7, metrics-server v0.9.0, local-path-provisioner v0.0.37 |

Note : le kubectl installé à part (v1.31.14) est loin de k3s v1.36.5. Pour le rejeu final, utiliser `sudo k3s kubectl` sur les deux clusters.

Preuve brute : `docs/evidence/tool-versions-zt-lab-a.txt`.
