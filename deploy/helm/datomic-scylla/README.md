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

The chart fails closed: it refuses to install on the default app/superuser
passwords, and Scylla 2026.2 ships no superuser of its own, so you must seed one
(see [Secrets in production](#secrets-in-production)).

```bash
kubectl create namespace datomic
# The hash must be of the same password you pass as secrets.superuserPassword.
SU_PASS='pick-a-real-password'
helm install datomic deploy/helm/datomic-scylla -n datomic \
  --set secrets.appPassword='another-real-password' \
  --set secrets.superuserPassword="$SU_PASS" \
  --set-string auth.superuserSaltedPassword="$(mkpasswd -m sha-512 "$SU_PASS")"
# provisioning runs before install returns; the Job is kept, so read its logs after
kubectl -n datomic logs job/datomic-datomic-scylla-provision
kubectl -n datomic logs statefulset/datomic-datomic-scylla | grep "System started"
```

Upgrade with `helm upgrade datomic deploy/helm/datomic-scylla -n datomic` (the
provisioning Job re-runs as a post-upgrade hook; it is idempotent).

## What it deploys

| Object | Purpose |
|---|---|
| `ScyllaCluster` | 3-member Scylla, password auth, Operator-managed server TLS (CQL on 9142). |
| ConfigMap (scylla-config) | `PasswordAuthenticator` + `CassandraAuthorizer`, and the seeded superuser. |
| Secret | App/superuser/keystore/truststore passwords (unless `secrets.existingSecret`). |
| Provisioning Job (Helm hook) | Keyspace/table/role at RF=3, over TLS. Only when `provisioning.enabled=true`. |
| StatefulSet (2 replicas) | Datomic transactor (active + standby); init container builds the truststore from Scylla's serving CA. |
| PodDisruptionBudget | Only when `datomic.pdb.enabled=true` (default). |
| Services | Headless (stable pod DNS) + ClusterIP (4334–4336 for in-cluster peers). |
| cert-manager Issuer/Certs | Only when `tls.mutual.enabled=true`. |

Backups are not part of this chart — use Scylla Manager.

## Key values

| Key | Default | Notes |
|---|---|---|
| `image.repository` / `image.tag` | `ghcr.io/whoiswentz/datomic-scylla-transactor` / `1.0.7705` | Transactor image. |
| `scylla.members` | `3` | Cluster size (RF is set by the provisioning Job). |
| `scylla.storageClassName` / `storageCapacity` | `""` (default SC) / `100Gi` | Per-member PVC. |
| `scylla.servingCAConfigMap` / `servingCAKey` | `datomic-scylla-local-serving-ca` / `tls.crt` | ConfigMap published by the Operator. **Verify** against your Operator version (the truststore is built from this). |
| `scylla.cpuset` | `true` | CPU pinning, which requires Guaranteed QoS. Set `false` on constrained clusters. |
| `datomic.replicas` | `2` | Active + standby HA. |
| `datomic.pdb.enabled` / `minAvailable` | `true` / `1` | Keeps one transactor up during voluntary disruptions. |
| `datomic.jvm` / `datomic.memory` | `-Xms4g/-Xmx4g` / … | Keep memory settings consistent with the heap. |
| `storage.cqlPort` | `9142` | TLS CQL (not 9042). |
| `storage.rf` | `3` | Replication factor. |
| `auth.superuserSaltedPassword` | `""` | **Required.** Salted hash seeding Scylla's first superuser. |
| `tls.mutual.enabled` | `false` | Opt into client-cert mutual TLS (needs cert-manager). |
| `secrets.existingSecret` | `""` | Reference a pre-created Secret for prod. |
| `provisioning.enabled` | `true` | Run the schema Job. |

## Secrets in production

Do **not** ship real secrets in `values.yaml`. Pre-create a Secret and set
`secrets.existingSecret`. It must contain these keys:

```
app-password, superuser-password, truststore-password, keystore-password
```

`app-password` and `superuser-password` are fail-closed: the chart refuses to
install while they hold their default values. The two PKCS12 store passwords are
not, because neither is a confidentiality boundary — the truststore holds only
Scylla's public serving CA, and cert-manager writes `keystore.p12` into the same
Secret that already holds its `tls.key` in the clear.

### Seeding the superuser

ScyllaDB 2026.2 removed the `cassandra`/`cassandra` default, so a fresh cluster
has no account at all until you seed one. That is what `auth.superuserSaltedPassword`
is for, and the install fails without it:

```bash
mkpasswd -m sha-512 'the-same-password-as-secrets.superuserPassword'
```

It is a salted hash rather than a password, which is why it can live in the
`scylla.yaml` ConfigMap that the Operator's `scyllaConfig` requires. Keep it in
sync with `secrets.superuserPassword` by hand: nothing validates the pair, and a
mismatch surfaces as the provisioning Job failing its login probe. Scylla ignores
both keys once the role exists, so rotating the superuser password afterwards
means an `ALTER ROLE` by hand.

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
- Confirm `scylla.servingCAConfigMap`/`Key` against the installed Operator version
  (Operator "Using CQL" docs).

## Verify without a cluster

`helm template` runs the fail-closed guards, so it needs credentials even for a
dry render — with none, it stops at the first `fail` rather than rendering. (Note
that `helm lint` passes either way, so it will not catch this.)

```bash
CREDS=(--set secrets.appPassword=x --set secrets.superuserPassword=y
       --set-string auth.superuserSaltedPassword='$6$salt$hash')

helm lint deploy/helm/datomic-scylla "${CREDS[@]}"
helm template datomic deploy/helm/datomic-scylla -n datomic "${CREDS[@]}"
helm template datomic deploy/helm/datomic-scylla -n datomic "${CREDS[@]}" --set tls.mutual.enabled=true
```

For a local minikube run, add `-f deploy/helm/datomic-scylla/values-minikube.yaml`
(scaled-down overrides for testing only — it does not set any credentials).
