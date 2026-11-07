# Comportement de Kyverno quand le contrôleur d'admission disparaît

Contexte : Kyverno (chart 3.9.2), **un seul réplica** du contrôleur d'admission, tous les webhooks en `failurePolicy=Fail`.
Méthode : `kubectl apply --dry-run=server` de deux pods dans `zt-attacker` (aucun pod créé) :
`ok` = `ghcr.io/stefanprodan/podinfo:6.7.1` (autorisé, épinglé), `bad` = `ghcr.io/stefanprodan/podinfo:latest` (viole seulement la règle du tag).
Preuves : `results-zt-lab-a-serie-a.txt` (arrêt propre) et `results-zt-lab-a-serie-b.txt` (plantage).

## Résultats
| Situation | `ok` | `bad` | Webhooks Kyverno | Comportement |
|---|---|---|---|---|
| Contrôleur actif (témoin) | accepté | refusé par la politique | 10 | normal |
| Arrêt propre (`scale --replicas=0`) | accepté | **accepté** | 10 → 2 | **fail-open** |
| Plantage (pod tué, `--force --grace-period=0`) | refusé | refusé | 10 (inchangé) | **fail-closed**, environ 30 s |
| Après rétablissement | accepté | refusé | 10 | protection revenue 9 s après la fin du rollout (arrêt propre) |

## Lecture
- Arrêt propre : Kyverno retire ses webhooks en s'arrêtant. Le cluster n'est plus protégé tant que le contrôleur n'est pas revenu et n'a pas réenregistré ses webhooks.
- Plantage : les webhooks restent déclarés, l'API Kubernetes ne joint plus Kyverno et applique `Fail` : toute création de pod est refusée, y compris les pods légitimes, jusqu'au retour du contrôleur (environ 30 s ici).

## Limites et pistes
- Un seul réplica : un arrêt propre ouvre le cluster, un plantage le bloque brièvement.
- Piste : 3 réplicas du contrôleur d'admission avec un PodDisruptionBudget (déploiement HA recommandé par Kyverno), non testée ici (VM mono-nœud).
- Procédure : ne jamais arrêter le contrôleur sur un cluster en production ; surveiller la présence des webhooks.
- Non testé : mise à jour progressive (rolling update) avec un seul réplica.

## Note de méthode
Une première tentative de simulation, en vidant le sélecteur du service `kyverno-svc`, n'a pas coupé le contrôleur : l'API Kubernetes a réutilisé la connexion déjà établie. Elle a été écartée.
