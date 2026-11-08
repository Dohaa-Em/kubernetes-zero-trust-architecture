# Relecture finale : Abir sur les parties de Doha (8 novembre 2026)

## Verifie et correct
| Element | Verification | Resultat |
| --- | --- | --- |
| Total Trivy | 65 + 107 + 26 + 24 = 222 (fichiers trivy-*.txt) | corrige dans le rapport (88b5e34), ancien total 239 faux |
| Vulnerabilites CRITICAL | 3 + 6 + 1 + 2 = 12 dans les fichiers de preuve | conforme |
| CVE citees (OpenSSL, brotli, stdlib Go, gRPC) | presentes dans les sorties Trivy, avec version corrigee | conforme |
| Rebuild zt-lab-b | 6/6 criteres, mesures S1-S4 identiques, ecart air-gap declare | conforme |

## Constats
| # | Emplacement | Probleme | Preuve | Correction proposee |
| --- | --- | --- | --- | --- |
| B1 | rapport section 6 et trivy-analysis.md section 1 | La cause est presentee comme l'age des tags pour les quatre images. Faux pour postgres : Alpine 3.24.4 est recent, les 26 failles viennent d'un binaire Go embarque ancien (stdlib v1.24.6) | trivy-postgres.txt (OS detecte et ligne stdlib) | Distinguer : OS ancien pour nginx, podinfo et curl ; binaire Go embarque pour postgres |
