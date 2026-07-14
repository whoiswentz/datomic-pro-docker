# Datomic Pro on ScyllaDB (Docker)

Production-ready, Docker-based [Datomic Pro](https://docs.datomic.com/) using
**ScyllaDB** as the storage engine, with password auth and mutual TLS between the
transactor and storage.

> **How ScyllaDB fits in.** Datomic has no native ScyllaDB backend. ScyllaDB is
> wire-compatible with Apache Cassandra, so Datomic talks to it through Datomic's
> **Cassandra** storage backend — specifically the modern **`cass3`** protocol
> (DataStax Java Driver V4), added in Datomic 1.0.7180. Datomic Pro is **free**;
> no license key is required.

- **Datomic Pro:** `1.0.7705`
- **Storage protocol:** `cass3`
- **Storage engine:** ScyllaDB (`scylladb/scylla` image)

## Architecture

```
                         docker network (compose)
  ┌──────────────┐   provision   ┌─────────────────────────────┐
  │ datomic-init │ ───(cqlsh)──▶ │  scylla  (auth + mutual TLS) │
  │ (one-shot)   │               │  9042 CQL                   │
  └──────┬───────┘               └─────────────┬───────────────┘
         │ completes ok                        │ cass3 (TLS + auth)
         ▼                                     │ direct reads
  ┌───────────────────────────┐  storage writes│
  │ datomic (transactor)      │◀───────────────┘
  │ cass3 → scylla            │
  │ 4334/4335/4336            │◀───────────────── peers (your apps)
  └───────────────────────────┘   transact / query
```

**Startup order:** `scylla` becomes healthy → `datomic-init` waits for
authenticated CQL over TLS and idempotently provisions the keyspace/table/role →
the `datomic` transactor renders its config from `.env`, mounts the certs, and
boots on `cass3`, ready to accept peer connections.

## Prerequisites

- Docker + Docker Compose v2.
- `openssl` (for `certs/generate-certs.sh`). If you don't have it on the host,
  run the generator in a container:
  `docker run --rm -v "$PWD/certs":/certs -w /certs alpine sh -c "apk add --no-cache openssl bash && ./generate-certs.sh"`.

## Quickstart (dev — single ScyllaDB node)

```bash
# 1. Configure
cp .env.example .env
#    → edit .env and change DATOMIC_DB_PASSWORD, TRUSTSTORE_PASSWORD, KEYSTORE_PASSWORD

# 2. Generate TLS material (writes into ./certs, which is gitignored)
./certs/generate-certs.sh

# 3. Bring up ScyllaDB → provisioning → transactor
docker compose up -d --build

# 4. Watch the transactor start
docker compose logs -f datomic          # look for "System started"
```

To connect from Clojure, see [`examples/clojure/`](examples/clojure/).

Tear down (and wipe storage): `docker compose down -v`.

## Configuration

All configuration lives in `.env` (copied from `.env.example`).

| Variable | Default | Purpose |
|---|---|---|
| `DATOMIC_VERSION` | `1.0.7705` | Datomic Pro version to download/run. |
| `TRANSACTOR_HOST` | `datomic` | Host the transactor advertises to peers (must be resolvable by them). On the compose network this is the service name. |
| `TRANSACTOR_XMX` / `TRANSACTOR_XMS` | `-Xmx1g` / `-Xms1g` | Transactor JVM heap. |
| `MEMORY_INDEX_THRESHOLD` / `MEMORY_INDEX_MAX` / `OBJECT_CACHE_MAX` | `32m` / `256m` / `128m` | Datomic memory/index/cache tuning; keep consistent with `-Xmx`. |
| `SCYLLA_VERSION` | `2026.2` | `scylladb/scylla` image tag. |
| `SCYLLA_CONTACT_POINTS` | `scylla` | Comma-separated Scylla hosts (a single contact point is enough — the driver discovers the rest). |
| `SCYLLA_CQL_PORT` | `9042` | Scylla CQL port. |
| `SCYLLA_KEYSPACE` / `SCYLLA_TABLE` | `datomic3` / `datomic3` | Keyspace + table (`cassandra-table` = `keyspace.table`). |
| `SCYLLA_DC` | `datacenter1` | Local datacenter — **required** by the V4 driver (`cassandra-local-datacenter`). Scylla's default DC is `datacenter1`. |
| `SCYLLA_RF` | `1` | Keyspace replication factor (dev=1; prod=3). |
| `CASSANDRA_SUPERUSER` / `CASSANDRA_SUPERUSER_PASSWORD` | `cassandra` / `cassandra` | Bootstrap superuser used **only** by `datomic-init`. Rotate/disable in prod. |
| `DATOMIC_DB_USER` / `DATOMIC_DB_PASSWORD` | `datomic3` / `change-me-app-password` | Least-privilege application role Datomic uses. Use a URL-safe password. |
| `CASSANDRA_SSL` | `true` | Enable TLS from the transactor to Scylla. |
| `SCYLLA_REQUIRE_CLIENT_AUTH` | `true` | Require a client certificate (mutual TLS). |
| `TRUSTSTORE_PASSWORD` / `KEYSTORE_PASSWORD` | placeholders | Passwords for the generated PKCS12 truststore/keystore. |

## TLS & authentication

`certs/generate-certs.sh` creates a private CA, signs a ScyllaDB **server**
certificate (SANs cover `scylla`, `scylla1..3`, `localhost`) and a Datomic
**client** certificate, and packages them for Java as PKCS12:

- `truststore.p12` — the CA, so Java clients trust the Scylla server cert.
- `keystore.p12` — the client identity, for mutual TLS.

ScyllaDB enforces this via `client_encryption_options` (`scylla/scylla.yaml`).
Java components (transactor, peer, backup jobs) receive the stores through
standard JVM system properties:

```
-Djavax.net.ssl.trustStore=/certs/truststore.p12 -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=…
-Djavax.net.ssl.keyStore=/certs/keystore.p12     -Djavax.net.ssl.keyStoreType=PKCS12   -Djavax.net.ssl.keyStorePassword=…
```

**Turning mutual TLS off** (keep encryption + server-cert verification, drop the
client-cert requirement): set `SCYLLA_REQUIRE_CLIENT_AUTH=false` in `.env`, set
`require_client_auth: false` in `scylla/scylla.yaml`, rebuild the Scylla image
(`docker compose build scylla`), and re-up. The transactor entrypoint then omits
the keystore.

**Rotating credentials:** change `DATOMIC_DB_PASSWORD` in `.env` and re-run
`docker compose up datomic-init` (the role's password is updated on next
provisioning if you switch `CREATE ROLE` to include an `ALTER ROLE`, or rotate
manually via `cqlsh`). Regenerate certs with `./certs/generate-certs.sh` and
rebuild the Scylla image to rotate TLS material.



## Production on Kubernetes

For production, deploy with the Helm chart at
[`deploy/helm/datomic-scylla/`](deploy/helm/datomic-scylla/) — ScyllaDB via the
**ScyllaDB Operator** (which also handles node tuning like `fs.aio-max-nr`),
a **2-replica** transactor StatefulSet on `cass3` over TLS (CQL port **9142**),
**cert-manager** for optional mutual TLS, and a Helm-hook provisioning Job.

```bash
# prereqs: ScyllaDB Operator + (optional) cert-manager installed; a default StorageClass;
# and the transactor image pushed to a registry the cluster can pull.
docker build -t ghcr.io/whoiswentz/datomic-scylla-transactor:1.0.7705 . && docker push ghcr.io/whoiswentz/datomic-scylla-transactor:1.0.7705
kubectl create namespace datomic
helm install datomic deploy/helm/datomic-scylla -n datomic
```

Dev stays on docker-compose (above). See the [chart README](deploy/helm/datomic-scylla/README.md)
for values, secrets, mutual-TLS, and cloud notes.

## Connecting a peer

Peers read storage **directly**, so they connect with a `cass3` URI and need the
truststore (and keystore, under mutual TLS) on their JVM:

```
datomic:cass3://<scylla-headless-svc>:9142/<keyspace>.<table>/<db-name>?user=<u>&password=<p>&ssl=true
```

`TRANSACTOR_HOST` must be resolvable by the peer (it's how the peer reaches the
transactor for writes). See [`examples/clojure/`](examples/clojure/) for a
runnable, commented walkthrough (connect, schema, transact, and query).

> **Peers need the Cassandra driver explicitly.** `com.datomic/peer` marks the
> DataStax V4 driver as optional, so a peer using `cass3` must add it to its deps
> at the version Datomic ships:
> `com.datastax.oss/java-driver-core-shaded {:mvn/version "4.17.0"}`. Without it
> you'll get `ClassNotFoundException: com.datastax.oss.driver.api.core.cql.ResultSet`.

## Backup & restore

Datomic-native backups (run inside the `datomic` container; output to `./backups`):

```bash
mkdir -p backups
./scripts/backup.sh  <db-name>                       # → ./backups/<db-name>
./scripts/restore.sh <db-name>                        # restore into Scylla

```

## Troubleshooting

- **Transactor can't be reached by peers** — `TRANSACTOR_HOST` must resolve to a
  reachable address for the peer. On the compose network use the service name
  (`datomic`); for external peers set it to a routable host and add `alt-host` to
  the transactor properties template.
- **`No node was available` / load-balancing errors** — the driver's
  `local-datacenter` must match Scylla's DC. Confirm with
  `docker compose exec scylla nodetool status` and set `SCYLLA_DC` accordingly.
- **TLS handshake failures** — ensure the Scylla server cert SAN includes the host
  you connect as (`scylla`), and that `TRUSTSTORE_PASSWORD`/`KEYSTORE_PASSWORD`
  match what `generate-certs.sh` used. Regenerate certs + rebuild the Scylla image
  after any `.env` password change.
- **Scylla healthy but auth is slow on first boot** — `PasswordAuthenticator`
  creates the default superuser asynchronously; `provision-storage.sh` retries for
  ~5 minutes.
- **Prod: `system_auth` under-replicated** — provisioning raises `system_auth` RF
  to match `SCYLLA_RF`; run `nodetool repair system_auth` after adding nodes.
- **Prod: a node stuck "health: starting" / `nodetool` errors with "Could not
  setup Async I/O ... aio-max-nr"** — raise `fs.aio-max-nr` (see Production notes).
  The node itself is usually fine; only `nodetool`/the healthcheck is failing.

## Versions & choices

- **Datomic 1.0.7705** — latest at time of writing; first `cass3` support was
  1.0.7180.
- **`cass3` (not `cass`/`cass2`)** — the current, non-legacy Cassandra backend on
  the actively-maintained DataStax V4 driver, best matched to modern ScyllaDB.
- Design and implementation notes: `docs/superpowers/specs/` and
  `docs/superpowers/plans/`.
