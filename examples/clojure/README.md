# Using Datomic-on-ScyllaDB from Clojure

A worked example: connect over `cass3`, install a schema, transact data, and
query it three ways (datalog, pull, entity). The code is in
[`src/example/core.clj`](src/example/core.clj).

## Run it

With the dev stack up from the repo root (`docker compose up -d --build`), run
this example from your host.

A Datomic peer reads ScyllaDB directly and reaches the transactor at the host it
advertises (`TRANSACTOR_HOST`, default `datomic`). To reach the dockerised stack
from your host, map those service names to `localhost` (the dev stack publishes
`9042` and `4334`) and point the JVM at the truststore/keystore:

```bash
# once: make the docker service names resolve to localhost
echo "127.0.0.1 scylla datomic" | sudo tee -a /etc/hosts

# from this folder — use your real credentials from the repo's .env
set -a && . ../../.env && set +a
clojure \
  -J-Djavax.net.ssl.trustStore=../../certs/truststore.p12 \
  -J-Djavax.net.ssl.trustStoreType=PKCS12 \
  -J-Djavax.net.ssl.trustStorePassword="$TRUSTSTORE_PASSWORD" \
  -J-Djavax.net.ssl.keyStore=../../certs/keystore.p12 \
  -J-Djavax.net.ssl.keyStoreType=PKCS12 \
  -J-Djavax.net.ssl.keyStorePassword="$KEYSTORE_PASSWORD" \
  -M -m example.core
```

The Scylla server certificate's SAN includes `scylla` and `localhost`, so TLS
validates against either name. For a REPL, start it with the same `-J` options
and call `(example.core/-main)` (or evaluate the `db-uri`/`d/connect` forms).

## Dependencies

`deps.edn` pins the peer and — because Datomic marks it optional — the DataStax
V4 driver at the version Datomic ships:

```clojure
com.datomic/peer                          {:mvn/version "1.0.7705"}
com.datastax.oss/java-driver-core-shaded  {:mvn/version "4.17.0"}
```

Without the driver you'll get
`ClassNotFoundException: com.datastax.oss.driver.api.core.cql.ResultSet`.
