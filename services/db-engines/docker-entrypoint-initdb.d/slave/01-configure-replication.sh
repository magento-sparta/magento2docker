#!/bin/bash
set -e

echo "Waiting for master (db) to be ready..."
until mysqladmin -h db -u root --password="" ping --silent 2>/dev/null; do
    sleep 2
done

# Detect vendor to choose the correct GTID syntax
DB_VERSION=$(mysql -h db -u root --password="" -N -e "SELECT VERSION()" 2>/dev/null)
if echo "$DB_VERSION" | grep -qi "mariadb"; then
    GTID_CLAUSE="MASTER_USE_GTID = slave_pos"
else
    GTID_CLAUSE="MASTER_AUTO_POSITION = 1"
fi

mysql -u root --password="" <<EOF
CHANGE MASTER TO
    MASTER_HOST     = 'db',
    MASTER_USER     = 'replication',
    MASTER_PASSWORD = 'replication',
    $GTID_CLAUSE;
START SLAVE;
EOF

echo "Replication started."
