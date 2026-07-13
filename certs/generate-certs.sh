#!/usr/bin/env bash
# Generates a self-signed CA and signs a ScyllaDB server cert + a Datomic client
# cert, then packages the client identity and CA trust as Java PKCS12 stores.
# openssl-only: no keytool / host JDK required.
#
#   ./certs/generate-certs.sh
#
# Passwords come from ../.env (TRUSTSTORE_PASSWORD, KEYSTORE_PASSWORD) if present.
# All output here is gitignored except this script and cqlshrc.
set -euo pipefail
cd "$(dirname "$0")"

[ -f ../.env ] && { set -a; . ../.env; set +a; }
TRUSTSTORE_PASSWORD="${TRUSTSTORE_PASSWORD:-change-me-truststore}"
KEYSTORE_PASSWORD="${KEYSTORE_PASSWORD:-change-me-keystore}"
DAYS="${CERT_DAYS:-3650}"
# SANs the Scylla server cert must cover (dev + prod node names + localhost).
SCYLLA_SANS="${SCYLLA_SANS:-DNS:scylla,DNS:scylla1,DNS:scylla2,DNS:scylla3,DNS:localhost,IP:127.0.0.1}"

echo "==> CA"
openssl req -x509 -newkey rsa:4096 -sha256 -days "$DAYS" -nodes \
  -keyout ca.key -out ca.crt -subj "/O=datomic-scylla/CN=datomic-scylla-ca"

sign() {  # name  subject  [sans]
  local name="$1" subj="$2" sans="${3:-}"
  openssl req -newkey rsa:4096 -sha256 -nodes \
    -keyout "${name}.key" -out "${name}.csr" -subj "$subj"
  local ext; ext="$(mktemp)"
  {
    echo "basicConstraints=CA:FALSE"
    echo "keyUsage=digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=serverAuth,clientAuth"
    [ -n "$sans" ] && echo "subjectAltName=${sans}"
  } > "$ext"
  openssl x509 -req -in "${name}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
    -sha256 -days "$DAYS" -extfile "$ext" -out "${name}.crt"
  rm -f "${name}.csr" "$ext"
}

echo "==> Scylla server cert"; sign scylla "/O=datomic-scylla/CN=scylla" "$SCYLLA_SANS"
echo "==> Datomic client cert"; sign client "/O=datomic-scylla/CN=datomic3"

echo "==> Java PKCS12 truststore (CA only)"
# Must use keytool: a truststore needs proper "trustedCertEntry" entries, which
# openssl's cert bags are not — Java's trust manager would see zero trust
# anchors ("trustAnchors parameter must be non-empty"). keytool creates them
# correctly. Falls back to a container if keytool isn't on the host.
keytool_cmd() {
  if command -v keytool >/dev/null 2>&1; then keytool "$@"
  else docker run --rm -v "$PWD":/w -w /w eclipse-temurin:17-jre keytool "$@"; fi
}
rm -f truststore.p12
keytool_cmd -importcert -noprompt -alias ca -file ca.crt \
  -keystore truststore.p12 -storetype PKCS12 -storepass "${TRUSTSTORE_PASSWORD}"

echo "==> Java PKCS12 keystore (client identity + chain)"
openssl pkcs12 -export -in client.crt -inkey client.key -certfile ca.crt \
  -name datomic -out keystore.p12 -passout "pass:${KEYSTORE_PASSWORD}"

# Raw private keys stay owner-only. The PKCS12 stores are password-encrypted, so
# they are group/world-readable — the non-root transactor container must read
# them from the read-only mount.
chmod 600 ./*.key
chmod 644 ./*.crt ./*.p12
echo "==> Done: ca.crt scylla.{crt,key} client.{crt,key} truststore.p12 keystore.p12"
