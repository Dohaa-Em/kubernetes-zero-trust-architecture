# Mesure : rbac
Date : 2026-11-03T23:09:29+02:00 | Machine : zt-lab-a | Noyau : 6.12.111+deb13-amd64 | k3s : k3s version v1.36.5+k3s1 (3dd98cc5)

## S1 : depuis le pod frontal compromis
| Cible | Résultat |
| --- | --- |
| API (zt-api:9898) | ATTEIGNABLE |
| Base (zt-data:5432) | ATTEIGNABLE |
| Serveur API Kubernetes | ATTEIGNABLE |
| Internet (1.1.1.1:443) | ATTEIGNABLE |

## S2 : droits du ServiceAccount sa-frontend
- Lire les Secrets de zt-data : yes
- Lire les Secrets de zt-frontend : yes
- Créer des pods dans zt-api : yes
- Exécuter dans un autre pod (zt-api) : yes
- Nombre de règles autorisées dans zt-data : 96

## S3 : un pod privilégié avec hostPath / est-il accepté ?
- ACCEPTÉ (aucun contrôle d'admission)

## S4 : le mot de passe de la base est-il lisible par le pod compromis ?
- OUI, lisible par sa-frontend
