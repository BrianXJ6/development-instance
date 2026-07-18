#!/bin/sh
# Creates the `testing` database and grants the app user access to it.
# Runs automatically on the MySQL container's FIRST boot only (mounted at
# /docker-entrypoint-initdb.d). Credentials come from the same env vars the
# official MySQL image already receives (MYSQL_USER / MYSQL_ROOT_PASSWORD) —
# nothing hardcoded, reusable across projects.
set -e

mysql --user=root --password="$MYSQL_ROOT_PASSWORD" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS testing
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_ci;

    GRANT ALL PRIVILEGES ON testing.* TO '$MYSQL_USER'@'%';

    FLUSH PRIVILEGES;
EOSQL
