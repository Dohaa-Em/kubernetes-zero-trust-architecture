# Relecture croisée : Abir Majdi relit le travail de Doha El Merabet

Périmètre relu : `secrets/` (Vault, ESO, rotation), `detection/` (Falco), `cluster/audit/` (audit, chiffrement), `scripts/harden-serviceaccounts.sh`.
Constats marqués « vérifié » : testés sur zt-lab-a le 7 novembre 2026.

## Points solides
- Aucun mot de passe en clair dans l'historique Git : seul un `secretKeyRef` vers `db-creds` apparaît (`git log -S POSTGRES_PASSWORD`).
- La clé de descellement passe dans le corps d'une requête HTTP et non en argument de `kubectl exec`, donc elle n'apparaît pas dans le journal d'audit.
- La politique d'audit enregistre les Secrets au niveau Metadata : les valeurs ne sont jamais écrites dans le journal.
- Les preuves de rotation n'affichent que l'empreinte SHA-256 du mot de passe.
- Exception de la sonde Vault dans Falco documentée avec sa limite.

## Constats

| N° | Gravité | Élément | Constat | Recommandation |
| --- | --- | --- | --- | --- |
| A1 | Moyenne | ESO, droits RBAC | **Vérifié.** Le ServiceAccount d'ESO peut lire les Secrets de tous les namespaces (`kube-system`, `vault`, `zt-api`, `zt-data` : `yes`) et en modifier (`update` dans `zt-api` : `yes`). Ce sont les droits par défaut du chart. La politique 70 n'empêche l'écriture que dans `zt-data`. Si ESO est compromis, tous les Secrets du cluster sont exposés. | Limiter ESO à `zt-data` (options `scopedRBAC` et `scopedNamespace` du chart, à tester), sinon documenter la limite dans le rapport. **Corrigé le 7 novembre sur zt-lab-a** : `scopedRBAC=true`, `scopedNamespace=zt-data`, ressources de niveau cluster désactivées. ESO synchronise toujours, la lecture des Secrets de `kube-system`, `vault` et `zt-api` est refusée (`docs/evidence/secrets-policy/eso-scoped-rbac-zt-lab-a.txt`). |
| A2 | Moyenne | Falco, règle `ZT Shell spawned in app container` | L'exclusion `not proc.cmdline contains "docker-entrypoint"` est contournable : un attaquant n'a qu'à écrire cette chaîne dans sa commande, par exemple `sh -c "echo docker-entrypoint; id"`. La limite est documentée pour la sonde Vault, pas pour cette règle. | Restreindre l'exclusion au processus parent réel (`proc.pname`) ou documenter la limite. **Corrigé le 7 novembre : exclusion supprimée** (le démarrage de nginx ne lance aucun shell, le contournement alerte ; `docs/evidence/detection/a2-docker-entrypoint-zt-lab-a.txt`, retest zt-lab-b par Doha, cab0036). |
| A3 | Faible | Falco, couverture | La règle de shell ne regarde que les noms de shells. `curl`, `wget` ou `nc` lancés directement ne déclenchent rien. Le journal d'audit (`exec` en Metadata) compense en partie. | Écrire cette limite dans la section détection du rapport. |
| A4 | Faible | Vault | **Observé.** Vault redevient scellé quand son pod redémarre (3 redémarrages en 22 h). ESO est resté en `SecretSyncedError` pendant 160 minutes jusqu'au descellement manuel. Il n'y a pas d'auto-unseal. | Limite de lab à documenter : descellement manuel, une seule clé, seuil 1, root token utilisé par les scripts, TLS désactivé. |
| A5 | Information | Rotation | Après `rotate-db-password.sh`, le pod garde l'ancien mot de passe en variable d'environnement jusqu'à son redémarrage. Le script l'indique déjà. | Reprendre cette limite dans le rapport (piste : rechargement applicatif ou redémarrage contrôlé). |
| A6 | Information | `harden-serviceaccounts.sh` | **Vérifié.** Le script ignore `kube-system` : ses ServiceAccounts gardent l'automount par défaut (seul `default` est à `false`). C'est justifié, les composants système ont besoin de leur jeton. Cela correspond au résultat kube-bench 5.1.6. | Aucune action, à citer comme décision justifiée. |

## Verdict
Pas de blocage pour le tag `v0.9-integration`. A1 et A2 sont à traiter ou à documenter avant la version finale.
