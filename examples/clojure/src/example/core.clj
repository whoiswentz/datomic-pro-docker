(ns example.core
  "Worked example: use Datomic Pro (ScyllaDB / cass3 backend) from Clojure —
  connect, install a schema, transact data, and query it (datalog, pull, entity).

  Run it on the compose network:  docker compose run --rm example
  Or from your own REPL / app:     see this folder's README.md"
  (:require [datomic.api :as d]
            [clojure.string :as str]
            [clojure.pprint :refer [pprint]])
  (:gen-class))

(defn- env [k default] (or (System/getenv k) default))

(defn db-uri
  "Build the cass3 connection URI from the environment. A Datomic peer reads
  storage (ScyllaDB) directly, so the URI carries the contact point, the app
  credentials, the TLS flag, and the driver's local datacenter."
  []
  (let [host (first (str/split (env "SCYLLA_CONTACT_POINTS" "scylla") #","))]
    (format "datomic:cass3://%s:%s/%s.%s/%s?user=%s&password=%s&ssl=true&local-datacenter=%s"
            host
            (env "SCYLLA_CQL_PORT" "9042")
            (env "SCYLLA_KEYSPACE" "datomic3")
            (env "SCYLLA_TABLE" "datomic3")
            (env "EXAMPLE_DB_NAME" "example")
            (env "DATOMIC_DB_USER" "datomic3")
            (env "DATOMIC_DB_PASSWORD" "change-me-app-password")
            (env "SCYLLA_DC" "datacenter1"))))

;; A Datomic schema is just data: each attribute is an entity described by
;; :db/ident, :db/valueType and :db/cardinality. Transacting it installs it.
(def schema
  [{:db/ident :user/email
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :user/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :post/title
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :post/body
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :post/author
    :db/valueType :db.type/ref            ; a reference to a :user entity
    :db/cardinality :db.cardinality/one}])

;; :user/email and :post/title are unique identities, so re-running this example
;; upserts rather than duplicating. Authors are referenced by a lookup ref.
(def sample-data
  [{:user/email "ada@example.com"  :user/name "Ada Lovelace"}
   {:user/email "alan@example.com" :user/name "Alan Turing"}
   {:post/title "On the Analytical Engine"
    :post/body  "Notes on Menabrea's memoir."
    :post/author [:user/email "ada@example.com"]}
   {:post/title "Computing Machinery and Intelligence"
    :post/body  "Can machines think?"
    :post/author [:user/email "alan@example.com"]}])

(defn -main [& _]
  (let [uri (db-uri)]
    (println "Connecting:"
             (str/replace uri (env "DATOMIC_DB_PASSWORD" "change-me-app-password") "***"))
    (d/create-database uri)                       ; no-op if the db already exists
    (let [conn (d/connect uri)]
      @(d/transact conn schema)                   ; install schema (idempotent)
      @(d/transact conn sample-data)              ; upsert data   (idempotent)
      (let [db (d/db conn)]

        (println "\n-- datalog: all users --")
        (pprint (d/q '[:find ?name ?email
                       :where
                       [?u :user/name ?name]
                       [?u :user/email ?email]]
                     db))

        (println "\n-- datalog + pull: posts with their author's name --")
        (pprint (d/q '[:find (pull ?p [:post/title {:post/author [:user/name]}])
                       :where [?p :post/title]]
                     db))

        (println "\n-- pull: one user by lookup ref --")
        (pprint (d/pull db [:user/name :user/email] [:user/email "ada@example.com"]))

        (println "\n-- entity: navigate a post -> its author --")
        (let [eid (d/q '[:find ?p . :where [?p :post/title "On the Analytical Engine"]] db)
              e   (d/entity db eid)]
          (println (format "\"%s\" — %s" (:post/title e) (:user/name (:post/author e))))))

      (println "\nDone.")
      (d/shutdown false)
      (System/exit 0))))
