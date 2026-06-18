#!/bin/bash
# Generate users.d/default-password.xml from CLICKHOUSE_PASSWORD env var
# on every container start, so the password survives volume-backed restarts.
set -e

PW="${CLICKHOUSE_PASSWORD:-open_epm_dev}"
mkdir -p /etc/clickhouse-server/users.d

cat > /etc/clickhouse-server/users.d/default-password.xml <<EOF
<clickhouse>
    <users>
        <default>
            <password>${PW}</password>
        </default>
    </users>
</clickhouse>
EOF

# Hand off to the official entrypoint
exec /entrypoint.sh "$@"
