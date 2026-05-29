#!/usr/bin/env bash
set -euo pipefail

WEB_USER="${WEB_USER:-arcboxweb}"
WEB_PASSWORD="${WEB_PASSWORD:?WEB_PASSWORD env var must be set}"
WEB_DB="${WEB_DB:-arcboxdemo}"
ALLOW_CIDR="${ALLOW_CIDR:-10.10.1.0/24}"

export DEBIAN_FRONTEND=noninteractive

echo 'Updating apt and installing PostgreSQL'
sudo apt-get update -y
sudo apt-get install -y postgresql postgresql-contrib

PG_VERSION=$(ls /etc/postgresql 2>/dev/null | sort -V | tail -n 1)
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

echo "Configuring PostgreSQL ${PG_VERSION} to listen on 0.0.0.0"
sudo sed -i "s/^#\?listen_addresses.*/listen_addresses = '*'/" "${PG_CONF}"

if ! sudo grep -qE "host\s+all\s+all\s+${ALLOW_CIDR//\//\\/}\s+md5" "${PG_HBA}"; then
    echo "host    all             all             ${ALLOW_CIDR}            md5" | sudo tee -a "${PG_HBA}" > /dev/null
fi

sudo systemctl restart postgresql

echo 'Provisioning role, database, and sample table'
SQL_BOOTSTRAP=$(cat <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${WEB_USER}') THEN
        CREATE ROLE ${WEB_USER} WITH LOGIN PASSWORD '${WEB_PASSWORD}';
    ELSE
        ALTER ROLE ${WEB_USER} WITH LOGIN PASSWORD '${WEB_PASSWORD}';
    END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${WEB_DB} OWNER ${WEB_USER}'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${WEB_DB}')\gexec
SQL
)
sudo -u postgres psql -v ON_ERROR_STOP=1 <<EOF
${SQL_BOOTSTRAP}
EOF

SQL_SEED=$(cat <<SQL
CREATE TABLE IF NOT EXISTS widgets (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    qty INTEGER NOT NULL
);
INSERT INTO widgets (name, qty)
SELECT v.name, v.qty
FROM (VALUES
    ('Hybrid Connector', 42),
    ('Edge Gateway', 17),
    ('Arc Probe', 8),
    ('Cloud Bridge', 23)
) AS v(name, qty)
WHERE NOT EXISTS (SELECT 1 FROM widgets WHERE widgets.name = v.name);
GRANT ALL ON widgets TO ${WEB_USER};
GRANT USAGE, SELECT ON SEQUENCE widgets_id_seq TO ${WEB_USER};
SQL
)
sudo -u postgres psql -d "${WEB_DB}" -v ON_ERROR_STOP=1 <<EOF
${SQL_SEED}
EOF

echo 'PostgreSQL configured and seeded'
