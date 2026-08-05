ARG M2D_DB_ENGINE_VENDOR='mariadb'
ARG M2D_DB_ENGINE_VERSION='10.2'
ARG M2D_ENABLE_DB_REPLICATION='no'

FROM mariadb:10.4 AS m2d_db_engine_mariadb_10

FROM mariadb:10.2 AS m2d_db_engine_mariadb_10.2
FROM mariadb:10.3 AS m2d_db_engine_mariadb_10.3
FROM mariadb:10.4 AS m2d_db_engine_mariadb_10.4
FROM mariadb:10.6 AS m2d_db_engine_mariadb_10.6
FROM mariadb:10.11 AS m2d_db_engine_mariadb_10.11
FROM mariadb:11.4 AS m2d_db_engine_mariadb_11.4

FROM --platform=linux/amd64 mysql:5.7 AS m2d_db_engine_mysql_5
FROM --platform=linux/amd64 mysql:8.0.28 AS m2d_db_engine_mysql_8

FROM --platform=linux/amd64 mysql:5.7 AS m2d_db_engine_mysql_5.7
FROM --platform=linux/amd64 mysql:8.0.28 AS m2d_db_engine_mysql_8.0
FROM mysql:8.0.28-oracle AS m2d_db_engine_mysql_8.0-oracle

# The master (`db`) is never itself optional — only whether it creates the replication
# account is. Split so that account only exists when M2D_ENABLE_DB_REPLICATION=yes at
# BUILD time (a deliberate opt-in via `bin/m2d enable db-replication` + a rebuild), instead
# of the account being created unconditionally on every single-node install.
FROM m2d_db_engine_${M2D_DB_ENGINE_VENDOR}_${M2D_DB_ENGINE_VERSION} AS m2d_db_engine_repl_no
COPY services/db-engines/etc/mysql/my.cnf /etc/mysql/conf.d/

FROM m2d_db_engine_${M2D_DB_ENGINE_VENDOR}_${M2D_DB_ENGINE_VERSION} AS m2d_db_engine_repl_yes
COPY services/db-engines/etc/mysql/my.cnf /etc/mysql/conf.d/
COPY services/db-engines/etc/mysql/my-replication.cnf /etc/mysql/conf.d/zz-replication.cnf
COPY services/db-engines/docker-entrypoint-initdb.d/master/ /docker-entrypoint-initdb.d/
CMD ["--init-file=/docker-entrypoint-initdb.d/01-replication-user.sql"]

FROM m2d_db_engine_repl_${M2D_ENABLE_DB_REPLICATION} AS m2d_db_engine

# The slave is genuinely optional — same busybox-placeholder pattern already used by
# every other M2D_ENABLE_* toggle in this repo (message brokers, search engines, caches).
FROM busybox:1.36 AS m2d_db_slave_engine_no
CMD ["tail", "-f", "/dev/null"]

FROM m2d_db_engine_${M2D_DB_ENGINE_VENDOR}_${M2D_DB_ENGINE_VERSION} AS m2d_db_slave_engine_yes
COPY services/db-engines/etc/mysql/my.cnf /etc/mysql/conf.d/
COPY services/db-engines/etc/mysql/my-replication.cnf /etc/mysql/conf.d/zz-replication.cnf
COPY services/db-engines/etc/mysql/my-slave.cnf /etc/mysql/conf.d/zz-slave.cnf
COPY services/db-engines/docker-entrypoint-initdb.d/slave/ /docker-entrypoint-initdb.d/

FROM m2d_db_slave_engine_${M2D_ENABLE_DB_REPLICATION} AS m2d_db_slave_engine
