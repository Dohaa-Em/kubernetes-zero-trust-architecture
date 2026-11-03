# Resultats baseline - zt-lab-a

- Date : 2026-11-03T20:08:19Z
- OS : Debian GNU/Linux 13 (trixie)
- k3s : k3s version v1.36.5+k3s1 (3dd98cc5)
- Cilium : quay.io/cilium/cilium:v1.20.4

## S1 - Pod frontend compromis (depuis le pod frontend)
| Cible | Resultat |
|---|---|
| API (zt-api:9898) | ATTEIGNABLE |
| Base de donnees (zt-data:5432) | ATTEIGNABLE |
| API Kubernetes (443) | ATTEIGNABLE |
| Internet (1.1.1.1:443) | ATTEIGNABLE |

## S1b - Pod attaquant (zt-attacker)
| Cible | Resultat |
|---|---|
| API depuis l'attaquant | ATTEIGNABLE |
| Internet depuis l'attaquant | ATTEIGNABLE |

## S2 - ServiceAccount sa-frontend vole
| Action | Resultat |
|---|---|
| lire les secrets de zt-data | yes |
| lire les secrets de zt-api | yes |
| creer des pods dans zt-data | yes |
| supprimer des deployments zt-api | yes |
| creer des roles dans zt-data | no |
| nb de lignes de droits dans zt-data | 96 |
| token monte dans le pod frontend | OUI |

## S3 - Configuration dangereuse (dry-run serveur)
| Pod privilegie + hostPath | ACCEPTE |

## S4 - Fuite du secret db-creds
| Test | Resultat |
|---|---|
| Lecture par sa-frontend | LISIBLE |
