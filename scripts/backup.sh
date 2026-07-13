#!/usr/bin/env bash
# Back up a Datomic database (stored in ScyllaDB) to ./backups/<db-name>.
# Runs inside the datomic container so the Datomic classpath + TLS certs are
# present.
#
#   scripts/backup.sh <db-name> [compose-file]
set -euo pipefail

DB="${1:?usage: backup.sh <db-name> [compose-file]}"
COMPOSE="${2:-docker-compose.yml}"
set -a; . ./.env; set +a

SRC="datomic:cass3://${SCYLLA_CONTACT_POINTS%%,*}:${SCYLLA_CQL_PORT}/${SCYLLA_KEYSPACE}.${SCYLLA_TABLE}/${DB}?user=${DATOMIC_DB_USER}&password=${DATOMIC_DB_PASSWORD}&ssl=true&local-datacenter=${SCYLLA_DC}"
DEST="file:///backups/${DB}"

TLS_OPTS="-Djavax.net.ssl.trustStore=/certs/truststore.p12 -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} -Djavax.net.ssl.keyStore=/certs/keystore.p12 -Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD}"

# -u root: the transactor runs non-root, but this admin task must write ./backups.
docker compose -f "$COMPOSE" exec -u root -e JAVA_TOOL_OPTIONS="$TLS_OPTS" \
  datomic ./bin/datomic backup-db "$SRC" "$DEST"
echo "Backup written to ./backups/${DB}"
