# Contribuer

Projet réalisé à deux, chacun sur sa propre VM et son propre cluster.

- Branche principale : `main`. Faire `git pull --rebase` avant chaque push.
- Un dossier a un responsable (voir `.github/CODEOWNERS`). Toute modification du dossier de l'autre se signale avant de pousser.
- Le contrat d'interface (`docs/01-interface-contract.md`) et `versions.md` se modifient seulement avec l'accord de l'autre.
- Messages de commit clairs : ce qui change et pourquoi.
- Aucun secret dans le dépôt, même de laboratoire.
- Chaque phase dépose ses preuves dans `docs/evidence/<phase>/<scénario>/` : commande, date, résultat brut.
- Pas de push forcé sur `main`.
