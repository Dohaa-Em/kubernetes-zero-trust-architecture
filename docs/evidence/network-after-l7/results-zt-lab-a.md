# Mesure : network-after-l7
Date : 2026-11-04T00:24:19+02:00 | Machine : zt-lab-a | Noyau : 6.12.111+deb13-amd64 | k3s : k3s version v1.36.5+k3s1 (3dd98cc5)

## S1 : depuis le pod frontal compromis
| Cible | Résultat |
| --- | --- |
| API (zt-api:9898) | ATTEIGNABLE |
| Base (zt-data:5432) | bloqué |
| Serveur API Kubernetes | bloqué |
| Internet (1.1.1.1:443) | bloqué |

## S2 : droits du ServiceAccount sa-frontend
- Lire les Secrets de zt-data : no
- Lire les Secrets de zt-frontend : no
- Créer des pods dans zt-api : no
- Exécuter dans un autre pod (zt-api) : no
- Nombre de règles autorisées dans zt-data : 23

## S3 : un pod privilégié avec hostPath / est-il accepté ?
- REFUSÉ

## S4 : le mot de passe de la base est-il lisible par le pod compromis ?
- non
