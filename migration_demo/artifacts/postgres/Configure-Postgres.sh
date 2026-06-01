#!/usr/bin/env bash
set -euo pipefail

WEB_USER="${WEB_USER:-arcboxweb}"
WEB_PASSWORD="${WEB_PASSWORD:?WEB_PASSWORD env var must be set}"
WEB_DB="${WEB_DB:-arcboxdemo}"
ALLOW_CIDR="${ALLOW_CIDR:-10.10.1.0/24}"

export DEBIAN_FRONTEND=noninteractive

echo 'Updating apt and installing PostgreSQL and web services'
sudo apt-get update -y
sudo apt-get install -y postgresql postgresql-contrib apache2 php libapache2-mod-php php-pgsql

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

echo 'Installing legacy PHP CRUD website'
sudo tee /var/www/html/index.php > /dev/null <<'PHP'
<?php
$dbName = '__WEB_DB__';
$dbUser = '__WEB_USER__';
$dbPassword = '__WEB_PASSWORD__';
$message = '';
$error = '';

function h($value) {
    return htmlspecialchars((string)$value, ENT_QUOTES, 'UTF-8');
}

try {
    $pdo = new PDO("pgsql:host=localhost;dbname={$dbName}", $dbUser, $dbPassword, array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION));

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $action = isset($_POST['action']) ? $_POST['action'] : '';
        if ($action === 'add' || $action === 'update') {
            $name = trim(isset($_POST['name']) ? $_POST['name'] : '');
            $qty = filter_input(INPUT_POST, 'qty', FILTER_VALIDATE_INT);
            if ($name === '' || $qty === false) {
                throw new Exception('Enter a name and numeric quantity.');
            }

            if ($action === 'add') {
                $stmt = $pdo->prepare('INSERT INTO widgets (name, qty) VALUES (:name, :qty)');
                $stmt->execute(array(':name' => $name, ':qty' => $qty));
                $message = 'Widget added.';
            } else {
                $id = filter_input(INPUT_POST, 'id', FILTER_VALIDATE_INT);
                if ($id === false) {
                    throw new Exception('Invalid widget id.');
                }
                $stmt = $pdo->prepare('UPDATE widgets SET name = :name, qty = :qty WHERE id = :id');
                $stmt->execute(array(':name' => $name, ':qty' => $qty, ':id' => $id));
                $message = 'Widget updated.';
            }
        } elseif ($action === 'delete') {
            $id = filter_input(INPUT_POST, 'id', FILTER_VALIDATE_INT);
            if ($id === false) {
                throw new Exception('Invalid widget id.');
            }
            $stmt = $pdo->prepare('DELETE FROM widgets WHERE id = :id');
            $stmt->execute(array(':id' => $id));
            $message = 'Widget deleted.';
        }
    }

    $rows = $pdo->query('SELECT id, name, qty FROM widgets ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
} catch (Exception $ex) {
    $rows = array();
    $error = $ex->getMessage();
}
?>
<!doctype html>
<html>
<head>
    <meta charset="utf-8" />
    <title>PostgreSQL CRUD - ArcBox</title>
    <style>
        body { font-family: Segoe UI, sans-serif; max-width: 760px; margin: 2em auto; color: #222; }
        h1 { color: #0078d4; }
        table { border-collapse: collapse; width: 100%; }
        th, td { padding: 0.4em 0.8em; border: 1px solid #ddd; text-align: left; }
        th { background: #f3f3f3; }
        input { width: 95%; padding: 0.35em; }
        button { padding: 0.4em 0.75em; margin-right: 0.25em; }
        .ok { color: #107c10; }
        .err { color: #a00; white-space: pre-wrap; }
    </style>
</head>
<body>
    <h1>PostgreSQL widgets</h1>
    <p>This legacy PHP page is hosted on <strong>ArcBox-Ubuntu</strong> and uses PostgreSQL database authentication.</p>
    <?php if ($message !== '') { ?><p class="ok"><?php echo h($message); ?></p><?php } ?>
    <?php if ($error !== '') { ?><p class="err">PostgreSQL error: <?php echo h($error); ?></p><?php } ?>

    <h2>Add widget</h2>
    <form method="post">
        <input type="hidden" name="action" value="add" />
        <p><label>Name<br /><input name="name" maxlength="100" required /></label></p>
        <p><label>Quantity<br /><input name="qty" type="number" min="0" required /></label></p>
        <button type="submit">Add</button>
    </form>

    <h2>Widgets</h2>
    <table>
        <tr><th>Id</th><th>Name</th><th>Quantity</th><th>Actions</th></tr>
        <?php foreach ($rows as $row) { ?>
        <tr>
            <form method="post">
                <td><?php echo h($row['id']); ?><input type="hidden" name="id" value="<?php echo h($row['id']); ?>" /></td>
                <td><input name="name" maxlength="100" value="<?php echo h($row['name']); ?>" /></td>
                <td><input name="qty" type="number" min="0" value="<?php echo h($row['qty']); ?>" /></td>
                <td><button name="action" value="update" type="submit">Save</button><button name="action" value="delete" type="submit">Delete</button></td>
            </form>
        </tr>
        <?php } ?>
    </table>
    <p><small>Host: <?php echo h(gethostname()); ?> &middot; Database: <?php echo h($dbName); ?></small></p>
</body>
</html>
PHP

sudo WEB_DB="${WEB_DB}" WEB_USER="${WEB_USER}" WEB_PASSWORD="${WEB_PASSWORD}" perl -0pi -e 's/__WEB_DB__/$ENV{WEB_DB}/g; s/__WEB_USER__/$ENV{WEB_USER}/g; s/__WEB_PASSWORD__/$ENV{WEB_PASSWORD}/g' /var/www/html/index.php
sudo chown www-data:www-data /var/www/html/index.php
sudo systemctl enable --now apache2
sudo systemctl restart apache2
sudo ufw allow 'Apache' >/dev/null 2>&1 || true

echo 'PostgreSQL, Apache, PHP, and the CRUD website are configured'
