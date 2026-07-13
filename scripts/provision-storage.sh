#!/usr/bin/env bash
# One-shot, idempotent storage provisioning for Datomic's cass3 backend.
# Waits until ScyllaDB accepts authenticated CQL over TLS, then creates the
# keyspace, table, and least-privilege application role, and rotates the
# built-in superuser password away from Scylla's default. Safe to re-run.
set -euo pipefail

HOST="${SCYLLA_CONTACT_POINTS%%,*}"        # first contact point
PORT="${SCYLLA_CQL_PORT:-9042}"
RF="${SCYLLA_RF:-1}"
AUTH_RF="${SCYLLA_SYSTEM_AUTH_RF:-$RF}"
KS="${SCYLLA_KEYSPACE:-datomic3}"
TBL="${SCYLLA_TABLE:-datomic3}"
SU="${CASSANDRA_SUPERUSER:-cassandra}"
SU_PASS="${CASSANDRA_SUPERUSER_PASSWORD:-cassandra}"
# Scylla's built-in superuser password, used to connect on the first run before
# the password has been rotated to CASSANDRA_SUPERUSER_PASSWORD.
SU_BOOTSTRAP="${CASSANDRA_SUPERUSER_BOOTSTRAP_PASSWORD:-cassandra}"

# Escape single quotes for safe interpolation into CQL string literals.
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
DB_PASS_ESC="$(esc "$DATOMIC_DB_PASSWORD")"
SU_PASS_ESC="$(esc "$SU_PASS")"

# cqlsh as the superuser with an explicit password.
cql_pw() { local pw="$1"; shift; cqlsh --ssl --cqlshrc=/certs/cqlshrc \
  -u "$SU" -p "$pw" "$HOST" "$PORT" "$@"; }

echo "==> Waiting for Scylla auth+TLS at ${HOST}:${PORT}"
ACTIVE_PW=""
for i in $(seq 1 60); do
  if cql_pw "$SU_PASS" -e "SELECT now() FROM system.local;" >/dev/null 2>&1; then
    ACTIVE_PW="$SU_PASS"; echo "    ready (superuser already rotated)"; break
  elif cql_pw "$SU_BOOTSTRAP" -e "SELECT now() FROM system.local;" >/dev/null 2>&1; then
    ACTIVE_PW="$SU_BOOTSTRAP"; echo "    ready (bootstrap superuser)"; break
  fi
  if [ "$i" = 60 ]; then echo "Scylla never became ready" >&2; exit 1; fi
  sleep 5
done

echo "==> Provisioning keyspace/table/role (idempotent)"
# NOTE: KS/TBL/user are CQL identifiers and must be valid identifiers (no quoting).
# Secrets are string literals and are single-quote escaped above.
cql_pw "$ACTIVE_PW" <<CQL
CREATE KEYSPACE IF NOT EXISTS ${KS}
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': ${RF}};

CREATE TABLE IF NOT EXISTS ${KS}.${TBL} (
  id2 text PRIMARY KEY,
  rev bigint,
  map text,
  val blob,
  chunks int
);

CREATE ROLE IF NOT EXISTS ${DATOMIC_DB_USER}
  WITH PASSWORD = '${DB_PASS_ESC}' AND LOGIN = true;
-- ALTER too: CREATE IF NOT EXISTS is a no-op when the role exists, so this
-- keeps the password in sync when DATOMIC_DB_PASSWORD changes and init re-runs.
ALTER ROLE ${DATOMIC_DB_USER}
  WITH PASSWORD = '${DB_PASS_ESC}' AND LOGIN = true;

GRANT ALL PERMISSIONS ON KEYSPACE ${KS} TO ${DATOMIC_DB_USER};

ALTER KEYSPACE system_auth
  WITH replication = {'class': 'SimpleStrategy', 'replication_factor': ${AUTH_RF}};
CQL

# Rotate the built-in superuser away from Scylla's default password.
if [ "$ACTIVE_PW" != "$SU_PASS" ]; then
  echo "==> Rotating superuser '${SU}' password"
  cql_pw "$ACTIVE_PW" -e "ALTER ROLE ${SU} WITH PASSWORD = '${SU_PASS_ESC}';"
fi

echo "==> Provisioning complete"
