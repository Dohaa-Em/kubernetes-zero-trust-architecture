# NetworkPolicy vs CiliumNetworkPolicy

| Criterion | Kubernetes NetworkPolicy | CiliumNetworkPolicy |
|---|---|---|
| Filtering level | L3/L4 (IP, port) | L3/L4 plus L7 (HTTP method and path) |
| Portability | Any CNI that supports it | Cilium only |
| Used in this project | Default deny and all production flows | Demonstration only (`network/extras/`) |
| Observability | Hubble shows verdicts | Hubble also shows HTTP requests |

Demo result: with the L7 rule, `GET /healthz` is forwarded and `GET /version` is denied
(see `docs/evidence/cilium-l7/`). The L7 policy is not applied by default: it needs the
L3/L4 allow rule removed first, and it ties the project to Cilium.
