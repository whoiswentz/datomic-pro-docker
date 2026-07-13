# datomic-scylla (Helm chart)

Production deployment of Datomic Pro on ScyllaDB (`cass3`) for Kubernetes. Dev
still uses docker-compose at the repo root; **this chart is the production path.**

## Prerequisites (installed separately, not by this chart)

1. **ScyllaDB Operator** + its CRDs. Recommended: a `NodeConfig` for the Scylla
   node pool to tune the kernel (`fs.aio-max-nr`, CPU pinning) — this replaces the
   manual `fs.aio-max-nr` step the compose setup needed.
2. **cert-manager** (only required if you enable mutual TLS).
3. A **default StorageClass** (SSD-backed recommended), or set
   `scylla.storageClassName`.
4. The **transactor image** pushed to a registry the cluster can pull, e.g.:
   ```bash
   docker build -t ghcr.io/whoiswentz/datomic-scylla-transactor:1.0.7705 .
   docker push ghcr.io/whoiswentz/datomic-scylla-transactor:1.0.7705
   ```

## Install

```bash
kubectl create namespace datomic
helm install datomic deploy/helm/datomic-scylla -n datomic
# watch provisioning + transactor
kubectl -n datomic logs job/datomic-datomic-scylla-provision
kubectl -n datomic logs statefulset/datomic-datomic-scylla | grep "System started"
```

Upgrade with `helm upgrade datomic deploy/helm/datomic-scylla -n datomic` (the
provisioning Job re-runs as a post-upgrade hook; it is idempotent).

## What it deploys

| Object | Purpose |
|---|---|
| `ScyllaCluster` | 3-member Scylla, password auth, Operator-managed server TLS (CQL on 9142). |
| ConfigMap (scylla-config) | `PasswordAuthenticator` + `CassandraAuthorizer`. |
| Secret | App/superuser/keystore/truststore passwords (unless `secrets.existingSecret`). |
| Provisioning Job (Helm hook) | Keyspace/table/role at RF=3, `system_auth` RF, superuser rotation, over TLS. |
| StatefulSet (2 replicas) | Datomic transactor (active + standby); init container builds the truststore from Scylla's serving CA. |
| Services | Headless (stable pod DNS) + ClusterIP (4334–4336 for in-cluster peers). |
| cert-manager Issuer/Certs | Only when `tls.mutual.enabled=true`. |
| CronJob | Only when `backups.enabled=true` (Scylla Manager is the primary backup). |

## Key values

| Key | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | `ghcr.io/whoiswentz/datomic-scylla-transactor` / `1.0.7705` | Transactor image. |
| `scylla.members` | `3` | Cluster size (RF is set by the provisioning Job). |
| `scylla.storageClassName` / `storageCapacity` | `""` (default SC) / `100Gi` | Per-member PVC. |
| `scylla.servingCASecret` / `servingCAKey` | `datomic-scylla-local-serving-ca` / `ca-bundle.crt` | **Verify** against your Operator version (the truststore is built from this). |
| `datomic.replicas` | `2` | Active + standby HA. |
| `datomic.jvm` / `datomic.memory` | `-Xms4g/-Xmx4g` / … | Keep memory settings consistent with the heap. |
| `storage.cqlPort` | `9142` | TLS CQL (not 9042). |
| `storage.rf` / `systemAuthRf` | `3` / `3` | Replication factor. |
| `tls.mutual.enabled` | `false` | Opt into client-cert mutual TLS (needs cert-manager). |
| `secrets.existingSecret` | `""` | Reference a pre-created Secret for prod. |
| `provisioning.enabled` | `true` | Run the schema Job. |
| `backups.enabled` | `false` | Optional Datomic backup CronJob. |

## Secrets in production

Do **not** ship real secrets in `values.yaml`. Pre-create a Secret and set
`secrets.existingSecret`. It must contain these keys:

```
app-password, superuser-password, superuser-bootstrap-password,
truststore-password, keystore-password
```

## Optional: mutual TLS

`--set tls.mutual.enabled=true` adds a cert-manager CA + client certificate
(with a PKCS12 keystore) and makes the transactor present it. You must also
configure Scylla to `require_client_auth` and trust the client CA (Operator
config) — see the design spec. Off by default; server-TLS + password auth is the
default posture.

## Cloud notes

- **EKS:** `gp3` StorageClass; ensure the Scylla node pool has the tuning
  `NodeConfig` and enough IOPS.
- **GKE:** `premium-rwo` (SSD) StorageClass; use a dedicated node pool for Scylla.
- **AKS:** `managed-csi-premium` StorageClass.
- Confirm `scylla.servingCASecret`/`Key` against the installed Operator version
  (Operator "Using CQL" docs).

## Verify without a cluster

```bash
helm lint deploy/helm/datomic-scylla
helm template datomic deploy/helm/datomic-scylla -n datomic
helm template datomic deploy/helm/datomic-scylla -n datomic --set tls.mutual.enabled=true
```
