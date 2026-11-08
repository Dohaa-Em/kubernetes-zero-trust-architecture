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
| B2 | docs/evidence/rebuild/rebuild-zt-lab-b.md, tableau de deroulement | Durees du tableau (environ 28 min au total, k3s ~4 min, etape 7 < 2 min) contredites par le journal brut (55 min, k3s 13:13-13:34, etape 7 14:00-14:06). Numerotation des etapes differente du README (le tableau met reseau et Kyverno en 7) | horodatages du journal brut du meme fichier ; rapport section 11 (55 min, 21 min, 13 min) coherent avec le brut | Corriger le tableau d'apres les horodatages et aligner les numeros sur le README |
| B3 | journal brut, 13:17 | Erreur secret-encrypt ID 89848 puis reussite a 13:25, sans explication, absente de la liste des trous | journal brut | Expliquer (demarrage lent de k3s) ou ajouter un trou : attendre le noeud Ready avant de verifier |
| B4 | journal brut 13:34 et trou A2 | ls /etc/cni/net.d a echoue (Permission non accordee) : le maintien du dossier apres k3s-uninstall n'est pas prouve, seul le noeud Ready avant Cilium le suggere | journal brut | Rejouer avec sudo ls /etc/cni/net.d juste apres la desinstallation et joindre la sortie (concerne aussi la ligne rm -rf du README, ecrite par Abir) |
| B5 | rapport section 8, question 6 | Parle de identifiants par defaut alors que la section 4.6.3 (ligne 369) et le modele de menace disent que l'interface Falcosidekick n'utilise plus admin:admin | report.md ligne 369 ; docs/00-threat-model.md section 5 | Preciser de quel outil il s'agit ou retirer default credentials |

## Verifie sans ecart
Preuves citees dans docs/00-threat-model.md (11 chemins) ; ports et flux des schemas docs/architecture (9898, 5432, 8200, 2801, 2802, 96 regles, commit 11cb1d4) ; ligne Images de la section 9 ; question 3.
