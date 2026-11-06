# Versions épinglées

Les deux membres installent exactement ces versions. À remplir au début de la phase 1.

| Outil | Version | Noyau / remarque |
| --- | --- | --- |
| Système, Abir Majdi (zt-lab-a) | Debian 13 | |
| Système, Doha (zt-lab-b) | Ubuntu 24.04 | noyau 6.14.0-35-generic, k3s v1.36.5+k3s1, Cilium 1.20.4 |
| k3s | | |
| Cilium | | |
| Hubble | | |
| Kyverno | | |
| Falco | | |
| Vault | | |
| External Secrets Operator | | |
| Helm | | |
- Kyverno chart: 3.9.2 (app v1.19.2)

## Versions mesurées sur zt-lab-a (Abir Majdi)

| Composant | Version |
|---|---|
| Debian / noyau | 13 / 6.12.111+deb13-amd64 |
| k3s | v1.36.5+k3s1 |
| Cilium (+ Hubble relay et UI) | 1.20.4 |
| cilium-cli | v0.20.2 |
| Hubble CLI | v1.20.2 |
| Helm | v3.22.1 |
| Kyverno chart / application | 3.9.2 / v1.19.2 |
| Kyverno CLI | 1.19.2 |
| Gitleaks | 8.30.1 |
| git / gh | 2.47.3 / 2.46.0 |
| kubectl | v1.31.14 |
| Image podinfo (frontend, API) | ghcr.io/stefanprodan/podinfo:6.7.1 |
| Image base de données | postgres:16-alpine |
| Image nginx | nginxinc/nginx-unprivileged:1.27-alpine |
| Image de test | curlimages/curl:8.10.1 |
| Composants k3s par défaut | CoreDNS 1.14.7, metrics-server v0.9.0, local-path-provisioner v0.0.37 |

Preuve brute : `docs/evidence/tool-versions-zt-lab-a.txt`.
