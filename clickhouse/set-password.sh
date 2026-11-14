#!/bin/bash
# Generate users.d/default-password.xml from CLICKHOUSE_PASSWORD env var
# on every container start, so the password survives volume-backed restarts.
#
# Also define konsol_measure_check (konsol#229) when
# CLICKHOUSE_MEASURE_CHECK_PASSWORD is set: the user konsol runs a Measure
# expression as before publishing it. The expression is SQL an EPM Admin
# writes, and ClickHouse evaluates a scalar subquery inside it even when the
# query reads no rows, so this user may SELECT only
# epm_silver.silver_gl_entries, read-only, for at most 5 seconds. No
# password, no user: konsol then reports expressions "not checked".
set -e

PW="${CLICKHOUSE_PASSWORD:-open_epm_dev}"
USERS_D="${CLICKHOUSE_USERS_D:-/etc/clickhouse-server/users.d}"
mkdir -p "$USERS_D"

cat > "$USERS_D/default-password.xml" <<EOF
<clickhouse>
    <users>
        <default>
            <password>${PW}</password>
        </default>
    </users>
</clickhouse>
EOF

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    fi
}

CHECK_XML="$USERS_D/measure-check.xml"
if [ -n "${CLICKHOUSE_MEASURE_CHECK_PASSWORD:-}" ]; then
    CHECK_HASH=$(sha256 "$CLICKHOUSE_MEASURE_CHECK_PASSWORD")
    cat > "$CHECK_XML" <<EOF
<clickhouse>
    <profiles>
        <konsol_measure_check>
            <readonly>1</readonly>
            <max_execution_time>5</max_execution_time>
            <timeout_overflow_mode>throw</timeout_overflow_mode>
            <cancel_http_readonly_queries_on_client_close>1</cancel_http_readonly_queries_on_client_close>
            <max_memory_usage>1000000000</max_memory_usage>
            <max_result_rows>1000</max_result_rows>
        </konsol_measure_check>
    </profiles>
    <quotas>
        <konsol_measure_check>
            <interval>
                <duration>60</duration>
                <queries>120</queries>
            </interval>
        </konsol_measure_check>
    </quotas>
    <users>
        <konsol_measure_check>
            <password_sha256_hex>${CHECK_HASH}</password_sha256_hex>
            <networks><ip>::/0</ip></networks>
            <profile>konsol_measure_check</profile>
            <quota>konsol_measure_check</quota>
            <access_management>0</access_management>
            <grants>
                <query>GRANT SELECT ON epm_silver.silver_gl_entries</query>
            </grants>
        </konsol_measure_check>
    </users>
</clickhouse>
EOF
else
    rm -f "$CHECK_XML"
fi

# Hand off to the official entrypoint
exec "${CLICKHOUSE_ENTRYPOINT:-/entrypoint.sh}" "$@"
