# Architecture

Trois vues de l'architecture du projet :
1. [Avant / après](#1-avant--après) : ce que pouvait faire un pod compromis, avant et après les contrôles Zero Trust ;
2. [Flux réseau autorisés](#2-flux-réseau-autorisés) : tout ce qui n'est pas sur ce schéma est refusé ;
3. [Flux des secrets Vault → ESO → base](#3-flux-des-secrets--vault--eso--base-de-données).

Les schémas sont en Mermaid, et GitHub les affiche directement.

Sources : les manifestes de `network/`, `admission/`, `rbac/`, `secrets/` et `detection/`, ainsi que les mesures `docs/evidence/baseline/` et `docs/evidence/integration/` (identiques sur zt-lab-a et zt-lab-b).

## 1. Avant / après

Scénario : le frontend est compromis (exécution de code dans le pod `frontend`).

### Avant (cluster par défaut, commit `11cb1d4`)

```mermaid
flowchart LR
    ATT(["Attaquant<br/>dans le pod frontend"])
    subgraph K8S["Cluster k3s par défaut"]
        FE["frontend<br/>SA sa-frontend"]
        API["api"]
        DB[("base PostgreSQL")]
        KAPI["API Kubernetes"]
        SEC["Secret db-creds<br/>en clair dans le datastore"]
        PRIV["Pod privilégié<br/>hostPath /"]
    end
    NET(("Internet"))

    ATT --> FE
    FE -->|"atteignable"| API
    FE -->|"atteignable"| DB
    FE -->|"atteignable"| KAPI
    FE -->|"atteignable"| NET
    FE -.->|"S2 : lit les Secrets, crée des pods,<br/>exec dans zt-api (96 règles)"| KAPI
    KAPI -.->|"S4 : mot de passe lisible"| SEC
    FE -.->|"S3 : accepté,<br/>aucune admission"| PRIV
```

### Après (Zero Trust)

```mermaid
flowchart LR
    ATT(["Attaquant<br/>dans le pod frontend"])
    subgraph K8S["Cluster k3s + Cilium"]
        FE["frontend<br/>non-root, FS lecture seule,<br/>sans jeton SA"]
        API["api"]
        DB[("base PostgreSQL")]
        KAPI["API Kubernetes<br/>audit des accès"]
        SEC["Secret db-creds<br/>chiffré AES-CBC,<br/>écrit seulement par ESO"]
        ADM{{"PSA restricted<br/>+ Kyverno"}}
        FALCO["Falco<br/>détection"]
    end
    NET(("Internet"))

    ATT --> FE
    FE ==>|"seul flux autorisé :<br/>TCP 9898"| API
    FE -. "bloqué" .-x DB
    FE -. "bloqué" .-x KAPI
    FE -. "bloqué" .-x NET
    FE -. "S2 : RBAC minimal,<br/>aucun droit sur les Secrets" .-x SEC
    FE -. "S3 : pod privilégié refusé" .-x ADM
    FALCO -. "surveille shell, lecture de jeton,<br/>sortie réseau de la base" .-> FE
```

| Mesure | Avant | Après | Contrôle responsable |
| --- | --- | --- | --- |
| S1 frontend → base | atteignable | bloqué | NetworkPolicy default deny + Cilium |
| S1 frontend → API Kubernetes | atteignable | bloqué | NetworkPolicy default deny + Cilium |
| S1 frontend → Internet | atteignable | bloqué | NetworkPolicy default deny + Cilium |
| S2 droits de `sa-frontend` | lit les Secrets, crée des pods, exec | aucun | RBAC minimal, pas de jeton monté |
| S3 pod privilégié + hostPath | accepté | refusé | Pod Security Admission `restricted` + Kyverno |
| S4 mot de passe lisible | oui | non | Vault + ESO, RBAC, Kyverno `secrets-only-from-eso` |

## 2. Flux réseau autorisés

Chaque namespace a une politique `default-deny-all` (entrée et sortie) et une règle DNS vers `kube-dns`. Le schéma montre les seules exceptions. Les flèches pointillées barrées sont des flux testés et refusés.

```mermaid
flowchart LR
    subgraph ZF["zt-frontend"]
        FE["frontend"]
    end
    subgraph ZA["zt-api"]
        API["api"]
    end
    subgraph ZD["zt-data"]
        DB[("postgres")]
        SEC["Secret db-creds"]
    end
    subgraph ZX["zt-attacker"]
        X["attacker"]
    end
    subgraph ESO_NS["external-secrets"]
        ESO["ESO controller"]
        WH["ESO webhook"]
    end
    subgraph V["vault"]
        VAULT["vault-0"]
    end
    subgraph F["falco"]
        FALCO["falco"]
        SK["falcosidekick"]
        UI["falcosidekick-ui"]
        REDIS[("redis")]
    end
    KAPI["API Kubernetes"]
    DNS["kube-dns"]
    NET(("Internet"))

    FE -->|"TCP 9898"| API
    API -->|"TCP 5432"| DB
    ESO -->|"TCP 8200"| VAULT
    ESO -->|"CNP : écrit db-creds"| KAPI
    KAPI -->|"CNP : webhook"| WH
    VAULT -->|"CNP : TokenReview"| KAPI
    FALCO --> SK
    SK --> UI
    UI --> REDIS
    FALCO -->|"CNP : mise à jour des règles"| NET

    FE -. "refusé" .-x DB
    FE -. "refusé" .-x NET
    DB -. "refusé + alerte Falco" .-x NET
    X -. "refusé" .-x API
    X -. "refusé" .-x VAULT
```

Tous les pods peuvent aussi joindre `kube-dns` sur le port 53 (règles `allow-dns-egress`). Pour ne pas surcharger le schéma, ces flux ne sont pas dessinés.

Le flux de la base vers Internet illustre la **défense en profondeur** : il est bloqué par Cilium, et la tentative est aussi détectée par Falco.

| Namespace | NetworkPolicy (Kubernetes) | CiliumNetworkPolicy (CNP) |
| --- | --- | --- |
| `zt-frontend` | default deny, DNS, sortie vers l'API | — |
| `zt-api` | default deny, DNS, entrée depuis le frontend, sortie vers la base | — |
| `zt-data` | default deny, DNS, entrée depuis l'API | — |
| `zt-attacker` | default deny, DNS | — |
| `external-secrets` | default deny, DNS, sortie vers Vault | sortie vers l'API Kubernetes, entrée du webhook |
| `vault` | default deny, DNS, entrée depuis ESO | sortie vers l'API Kubernetes |
| `falco` | default deny, Falco → sidekick → UI → redis | DNS, téléchargement des règles |

Les flux vers l'API Kubernetes passent par des CiliumNetworkPolicy (entité `kube-apiserver`). Une NetworkPolicy standard ne peut pas les exprimer de façon fiable, car l'adresse de l'API dépend du nœud.

## 3. Flux des secrets : Vault → ESO → base de données

Le mot de passe de la base n'existe que dans Vault. ESO le recopie dans le Secret Kubernetes `zt-data/db-creds`, seul objet que la base consomme. Aucun humain ni aucun autre pod ne peut écrire ce Secret (politique Kyverno `secrets-only-from-eso`).

```mermaid
sequenceDiagram
    autonumber
    participant ESO as ESO controller<br/>(external-secrets)
    participant KAPI as API Kubernetes
    participant V as Vault<br/>(auth kubernetes)
    participant S as Secret zt-data/db-creds<br/>(chiffré au repos)
    participant DB as postgres (zt-data)

    Note over ESO: SecretStore "vault" (namespacé, zt-data)<br/>ExternalSecret db-creds, refresh 1 min
    ESO->>KAPI: TokenRequest pour le SA zt-data/eso-vault<br/>(audience "vault")
    KAPI-->>ESO: jeton court
    ESO->>V: login, rôle "eso" + jeton
    V->>KAPI: TokenReview (le jeton est-il valide ?)
    KAPI-->>V: oui, SA eso-vault dans zt-data
    V-->>ESO: jeton Vault (TTL 15 min)<br/>policy zt-database-read
    ESO->>V: lecture secret/data/zt/database/*
    Note over V: chaque requête est tracée<br/>dans l'audit device de Vault
    V-->>ESO: mot de passe
    ESO->>KAPI: écrit / met à jour db-creds
    Note over KAPI: audit des accès aux Secrets (niveau Metadata)<br/>chiffrement AES-CBC dans le datastore
    KAPI->>S: stockage chiffré
    S-->>DB: injecté en variable d'environnement<br/>(secretKeyRef, clé password)
```

### Rotation (`secrets/rotate-db-password.sh`)

```mermaid
flowchart LR
    A["1. nouveau mot de passe<br/>dans PostgreSQL (psql via stdin)"] --> B["2. écriture dans Vault<br/>secret/zt/database"]
    B --> C["3. ESO force-sync"]
    C --> D["4. db-creds mis à jour<br/>(vérifié par hash)"]
    D --> E["5. test de connexion TCP"]
```

Les secrets passent toujours par l'entrée standard (stdin), jamais en argument de commande : les arguments de `kubectl exec` apparaissent en clair dans le journal d'audit.

### Ce que voit chaque identité

| Identité | Vault | Secret `db-creds` |
| --- | --- | --- |
| SA `zt-data/eso-vault` (via ESO) | lecture de `secret/data/zt/database/*` seulement | écriture (seul écrivain autorisé) |
| SA `sa-frontend` | login refusé | aucun droit |
| SA `sa-attacker` | login refusé | aucun droit |
| Administrateur du cluster | — | lecture possible, **écriture refusée** par Kyverno (relecture R10) |
