#!/usr/bin/env bash
# Restore a Datomic database from ./backups/<db-name> back into ScyllaDB.
# Runs inside the datomic container.
#
#   scripts/restore.sh <db-name> [compose-file]
set -euo pipefail

DB="${1:?usage: restore.sh <db-name> [compose-file]}"
COMPOSE="${2:-docker-compose.yml}"
set -a; . ./.env; set +a

SRC="file:///backups/${DB}"
DEST="datomic:cass3://${SCYLLA_CONTACT_POINTS%%,*}:${SCYLLA_CQL_PORT}/${SCYLLA_KEYSPACE}.${SCYLLA_TABLE}/${DB}?user=${DATOMIC_DB_USER}&password=${DATOMIC_DB_PASSWORD}&ssl=true&local-datacenter=${SCYLLA_DC}"

TLS_OPTS="-Djavax.net.ssl.trustStore=/certs/truststore.p12 -Djavax.net.ssl.trustStoreType=PKCS12 -Djavax.net.ssl.trustStorePassword=${TRUSTSTORE_PASSWORD} -Djavax.net.ssl.keyStore=/certs/keystore.p12 -Djavax.net.ssl.keyStoreType=PKCS12 -Djavax.net.ssl.keyStorePassword=${KEYSTORE_PASSWORD}"

# -u root: the transactor runs non-root, but this admin task reads ./backups.
docker compose -f "$COMPOSE" exec -u root -e JAVA_TOOL_OPTIONS="$TLS_OPTS" \
  datomic ./bin/datomic restore-db "$SRC" "$DEST"
echo "Restored ${DB} into ScyllaDB."
