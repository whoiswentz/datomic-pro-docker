#!/usr/bin/env bash
# Renders the transactor properties from environment, assembles the JVM TLS
# options, and launches the Datomic transactor on the cass3 backend.
set -euo pipefail

RENDERED="${DATOMIC_HOME}/config/cass3-transactor.properties"
envsubst < /opt/templates/transactor.properties.tmpl > "$RENDERED"
echo "==> Rendered transactor config:"
sed 's/\(password=\).*/\1***/' "$RENDERED"

# bin/transactor DROPS its default JVM flags as soon as any custom opt is
# passed, so we re-supply the defaults alongside the TLS system properties.
JVM_OPTS=(--enable-native-access=ALL-UNNAMED -XX:+UseG1GC -XX:MaxGCPauseMillis=50)

if [ "${CASSANDRA_SSL:-true}" = "true" ]; then
  JVM_OPTS+=(
    -Djavax.net.ssl.trustStore=/certs/truststore.p12
    -Djavax.net.ssl.trustStoreType=PKCS12
    -Djavax.net.ssl.trustStorePassword="${TRUSTSTORE_PASSWORD}"
  )
  if [ "${SCYLLA_REQUIRE_CLIENT_AUTH:-true}" = "true" ]; then
    KEYSTORE_PATH="/certs/keystore.p12"
    if [ -f "/client/keystore.p12" ]; then
      KEYSTORE_PATH="/client/keystore.p12"
    fi
    JVM_OPTS+=(
      -Djavax.net.ssl.keyStore="${KEYSTORE_PATH}"
      -Djavax.net.ssl.keyStoreType=PKCS12
      -Djavax.net.ssl.keyStorePassword="${KEYSTORE_PASSWORD}"
    )
  fi
fi

echo "==> Launching transactor (cass3)"
exec ./bin/transactor "${TRANSACTOR_XMS:--Xms1g}" "${TRANSACTOR_XMX:--Xmx1g}" "${JVM_OPTS[@]}" "$RENDERED"
