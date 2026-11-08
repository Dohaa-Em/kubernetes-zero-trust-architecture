# Relecture finale : Doha sur les parties d'Abir (8 novembre 2026)

Base relue : `3b8d53d`. Périmètre : rapport sections 4.2 à 4.4, 8 (questions 1 à 3), 9, 11 (reconstruction zt-lab-a), annexe A, et `docs/evidence/final/kubescape-analysis.md`.
Méthode : chaque chiffre est comparé au fichier de preuve cité ; chaque commit est vérifié avec `git cat-file -e`, et chaque chemin cité dans le rapport avec `ls`.

## Vérifié et correct

| Élément | Vérification | Résultat |
| --- | --- | --- |
| 4.2 : règles de `sa-frontend` dans `zt-data`, 96 → 23 | `docs/evidence/baseline/` et `docs/evidence/integration/` (S2) | conforme |
| 4.2 : permissions dangereuses, 5 comptes | `rbac/dangerous-permissions-zt-lab-a.txt` : 7 contrôles × 5 comptes à `no`, plus le contrôle `* *` corrigé à `no` | conforme (voir C6) |
| 4.3 : frontend → base, API Kubernetes, Internet bloqués | `network/hubble-frontend-flows-zt-lab-a.txt` : `EGRESS DENIED` et `DROPPED` pour les 3 cibles | conforme (voir C4) |
| 4.3 : API → base ouvert, frontend → base bloqué | `network/api-to-database-zt-lab-a.txt` : `succeeded`, puis `timed out`, Hubble `FORWARDED` | conforme |
| 4.3 : attaquant → Vault bloqué (`http=000`, code 28) et alerte Falco arrivée dans l'interface (`POST OK (200)`) | `network-vault-falco/results-zt-lab-a.txt` et `-zt-lab-b.txt` | conforme sur les deux clusters |
| 4.4 : webhooks 10 → 2 à l'arrêt propre, protection revenue 9 s après le rollout | `fail-mode/results-zt-lab-a-serie-a.txt` | conforme |
| 4.4 : blocage d'environ 30 s après un plantage | `serie-b` : kill à 18:41:36, refus jusqu'à 18:42:03, accepté à 18:42:09 (27 à 33 s) | conforme |
| 4.4 : liste blanche d'images, exception `latest-exception-*` dans `zt-attacker`, `allowExistingViolations: false` | `admission/30-restrict-images.yaml`, `60-policy-exception.yaml`, `70-secrets-only-from-eso.yaml` | conforme |
| Commits cités (`8441fdf`, `8ca98b2`, `961d229` du 3 novembre, `2549f76`, `88b5e34`, `b3451c7`) | `git log -1` | tous présents, dates et sujets cohérents |
| Chemins cités dans le rapport | `ls` de chaque chemin entre backticks | tous présents (hors chemins du nœud) |
| Versions citées dans le rapport | comparaison avec `versions.md` | identiques (voir C5 pour Trivy) |
| Kubescape : NSA 68,07 → 68,75, MITRE 65,11, couverture 38/40 (C-0069, C-0070) | `final/kubescape-zt-lab-a-before.txt` et `-after.txt` | conforme |
| Kubescape C-0013 : ressources en échec 10 → 7 | même fichiers | conforme avec 3 charges de travail corrigées (voir C1) |
| 11 : reconstruction zt-lab-a, 47 min, 6 critères, 3 trous corrigés dans `2549f76` | `rebuild/rebuild-zt-lab-a.md`, `criteres-zt-lab-a.txt` | conforme ; note `disallow-latest-tag` bien ajoutée |
| 10 : 895 MiB avec Kyverno, 589 MiB sans, ratio ≈ 26 | somme du tableau (303 + 124 + 46 + 116 + 306) / 35 = 25,6 | conforme |
| Questions 1 à 3 | cohérentes avec 4.2, 4.5 et 5, mêmes noms (S1 à S4, R1, R10, A1) | conforme |

## Constats

| # | Emplacement | Problème | Preuve | Correction proposée |
| --- | --- | --- | --- | --- |
| C1 | `kubescape-analysis.md` (introduction et § 1), rapport section 6 | Le texte affirme « aucun échec sur `zt-*` » et désigne `frontend`, `api` et `attacker` pour C-0013. Les fichiers de preuve ne contiennent que le résumé par contrôle, sans nom de ressource : l'affirmation n'est donc pas démontrée par la preuve citée. | `grep -c "zt-" kubescape-zt-lab-a-*.txt` donne 0 ; C-0013 passe de 10 à 7, ce qui est cohérent mais ne dit pas quelles ressources | Ajouter un scan détaillé limité aux namespaces `zt-*` (par exemple `kubescape scan framework nsa,mitre --include-namespaces zt-frontend,zt-api,zt-data,zt-attacker`), ou écrire « C-0013 passe de 10 à 7 ressources en échec, ce qui correspond aux 3 charges de travail corrigées » |
| C2 | `kubescape-analysis.md` § 3 | Les composants tiers totalisent 16 + 6 + 4 + 3 = 29 ressources, mais le scan « après » compte 47 ressources en échec. Les 18 restantes ne sont pas expliquées. | `kubescape-zt-lab-a-after.txt`, ligne `Failed Resources : 47` | Donner la répartition complète (ressources cluster, `default`, `cilium-secrets`…), ou retirer les chiffres par composant |
| C3 | `kubescape-analysis.md` | Trois contrôles en « Action Required » ne sont pas mentionnés : *Secret/etcd encryption enabled*, *Audit logs enabled* et *PSP enabled*. Kubescape ne peut pas les vérifier sur k3s, alors que le projet les couvre. | `kubescape-zt-lab-a-after.txt`, lignes 154, 160 et 178 | Ajouter un paragraphe « non vérifiable par Kubescape, vérifié autrement » : chiffrement → `docs/evidence/etcd-encryption/`, audit → `docs/evidence/audit/`, PSP supprimé depuis Kubernetes 1.25 et remplacé par PSA (4.4) |
| C4 | Rapport 4.3, extrait Hubble | L'extrait est raccourci (identifiants `(ID:…)` retirés, une seule ligne gardée par retransmission) sans que ce soit signalé, alors qu'il est présenté comme une capture. | `network/hubble-frontend-flows-zt-lab-a.txt`, lignes 12 à 21 | Ajouter « (extrait abrégé : identités et retransmissions retirées) » au-dessus du bloc |
| C5 | `versions.md` | Trivy 0.76.2, utilisé en section 6, n'est pas dans le tableau des versions. Le critère (e) demande des versions identiques à `versions.md`. | rapport section 6 ; `docs/evidence/final/trivy-*.txt` (en-tête) | Ajouter la ligne « Trivy \| 0.76.2 \| images lues dans containerd, zt-lab-b (Doha El Merabet) ». Je peux l'ajouter si tu es d'accord, c'est ton fichier |
| C6 | `rbac/dangerous-permissions-zt-lab-a.txt` | Dans le premier bloc, la ligne `* * -A` n'a pas de réponse pour les 5 comptes. Le bloc « Contrôle corrigé » à la fin du fichier donne bien `no`, mais un lecteur pressé peut croire à un trou. | lignes `* * -A` du fichier | Une ligne de commentaire en tête du fichier : « la vérification `* *` du premier bloc est vide, elle est refaite et corrigée à la fin du fichier » |
| C7 | Rapport 4.4 (« `allowExistingViolations: true` since version 1.13 ») | Fait externe, sans source citée. | aucune | Ajouter le lien vers la documentation Kyverno, ou retirer « since version 1.13 » |

## Corrections de mes propres sections (suite à B1 et relecture de moi-même)

| # | Emplacement | Correction |
| --- | --- | --- |
| B1 | Rapport section 6, `trivy-analysis.md` § 1 et § 2 | Cause distinguée par image : OS Alpine ancien pour nginx, podinfo et curl ; pour postgres, OS récent (Alpine 3.24.4, aucune faille) et les 26 résultats viennent du seul binaire Go `usr/local/bin/gosu` (stdlib v1.24.6). J'ai aussi retiré l'affirmation non prouvée « datent de plus d'un an ». |
| B2 | `rebuild-zt-lab-b.md` (tableau) et rapport section 11 | Trouvé en relisant mon journal avec la même méthode : la numérotation des étapes ne suivait pas celle du README, et plusieurs durées étaient sous-estimées. Le tableau est refait d'après les horodatages du journal brut : 55 min au total, dont 21 pour l'étape 2 (k3s et import des images) et 13 pour Vault. Les trous sont renommés « trou 1 à 3 » pour ne plus entrer en collision avec A1 et A2 de la relecture, et le texte indique que tes deux corrections sont dans `88b5e34`. |
