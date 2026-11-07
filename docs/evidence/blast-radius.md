| Etape | API | Base | API K8s | Internet | Secrets zt-data | Creer pods | S3 pod dangereux | S4 secret |
|---|---|---|---|---|---|---|---|---|
| baseline | ATTEIGNABLE | ATTEIGNABLE | ATTEIGNABLE | ATTEIGNABLE | yes | yes | ACCEPTÉ | OUI |
| rbac | ATTEIGNABLE | ATTEIGNABLE | ATTEIGNABLE | ATTEIGNABLE | no | no | ACCEPTÉ | non |
| network | ATTEIGNABLE | bloqué | bloqué | bloqué | no | no | ACCEPTÉ | non |
| admission-psa | ATTEIGNABLE | bloqué | bloqué | bloqué | no | no | REFUSÉ | non |
| admission-kyverno | ATTEIGNABLE | bloqué | bloqué | bloqué | no | no | REFUSÉ | non |
| integration (+ Vault/ESO + Falco) | ATTEIGNABLE | bloqué | bloqué | bloqué | no | no | REFUSÉ | non |
