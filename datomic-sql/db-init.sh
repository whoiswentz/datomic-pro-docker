psql -f tmp/datomic-sql-init/postgres-db.sql -U postgres
psql -f tmp/datomic-sql-init/postgres-table.sql -U postgres -d datomic
psql -f tmp/datomic-sql-init/postgres-user.sql -U postgres -d datomic