#!/bin/bash
# demo.sh — switch the public trial ("demo mode") of the second stack on or off,
# take its golden snapshot, and reset it to that snapshot.
#
#   demo.sh status              what is on, when the last reset ran, how old the golden copy is
#   demo.sh snapshot            take the golden copy of the site as it is NOW (deliberate, never automatic)
#   demo.sh on                  set demo_user in site_config, clear the cache, start the hourly reset timer
#   demo.sh off                 remove demo_user, end the demo user's sessions, stop the timer
#   demo.sh reset               restore the golden copy (database + files), resync the warehouse, dbt build
#
# Decided 7 Nov 2026 by Deepak Pai: the demo is switchable, resets hourly, the demo user holds
# EPM Analyst + Entity Accountant. konsol reads exactly one key, site_config `demo_user`
# (konsol/demo_mode.py); everything else lives here. Runs as root on the demo server.
# Never touches the live stack (/root/konsolidat, containers konsolidat_*).
set -euo pipefail

EXT_DIR=${EXT_DIR:-/root/konsolidat-ext}
SITE=${SITE:-demo-ext.konsolidat.com}
DEMO_USER=${DEMO_USER:-demo@konsolidat.com}
GOLDEN=$EXT_DIR/golden
LOG=$EXT_DIR/reset.log
TIMER=konsolidat-demo-reset.timer
BACKEND=konsolidat-ext_backend
BENCH_DIR=/home/frappe/frappe-bench
SITE_DIR=$BENCH_DIR/sites/$SITE
DC="docker compose -p konsolidat-ext --env-file $EXT_DIR/.env -f $EXT_DIR/docker-compose.yml -f $EXT_DIR/docker-compose.ext.yml"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
bench_in() { docker exec "$BACKEND" bash -lc "cd $BENCH_DIR && bench --site $SITE $*" 2>&1 | grep -v RuntimeWarning || true; }
need_golden() { [ -f "$GOLDEN/database.sql.gz" ] || { echo "no golden copy in $GOLDEN: run 'demo.sh snapshot' first" >&2; exit 2; }; }

cmd_status() {
  echo "site:        $SITE"
  echo "demo_user:   $(docker exec "$BACKEND" python3 -c "import json;print(json.load(open('$SITE_DIR/site_config.json')).get('demo_user') or '(off)')" 2>/dev/null || echo '?')"
  echo "timer:       $(systemctl is-enabled $TIMER 2>/dev/null || echo not-installed) / $(systemctl is-active $TIMER 2>/dev/null || echo inactive)"
  systemctl list-timers --no-pager "$TIMER" 2>/dev/null | sed -n 2p | sed 's/^/             /' || true
  if [ -f "$GOLDEN/database.sql.gz" ]; then echo "golden:      $(date -u -r "$GOLDEN/database.sql.gz" +%FT%TZ) ($(du -sh "$GOLDEN" | cut -f1))"; else echo "golden:      none"; fi
  echo "last reset:  $(grep -h 'reset done' "$LOG" 2>/dev/null | tail -1 || echo never)"
}

cmd_snapshot() {
  # The golden copy is what every reset returns to. Taking it is a decision, so it is a command,
  # not a timer: check the site first (data loaded, builds green, demo user present).
  log "snapshot: backing up $SITE with files"
  bench_in "backup --with-files --backup-path $SITE_DIR/private/backups/golden"
  mkdir -p "$GOLDEN"
  rm -f "$GOLDEN"/*
  docker cp "$BACKEND:$SITE_DIR/private/backups/golden/." "$GOLDEN/"
  # normalise names: one database, one private, one public archive
  ( cd "$GOLDEN" && for f in *-database.sql.gz; do mv "$f" database.sql.gz; done \
    && for f in *-private-files.tar; do mv "$f" private-files.tar; done \
    && for f in *-files.tar; do mv "$f" public-files.tar; done ) 2>/dev/null || true
  docker exec "$BACKEND" rm -rf "$SITE_DIR/private/backups/golden"
  ls -la "$GOLDEN"
  log "snapshot done"
}

cmd_on() {
  log "on: demo_user=$DEMO_USER"
  bench_in "set-config demo_user $DEMO_USER"
  bench_in "clear-cache"
  install_timer
  systemctl enable --now $TIMER
  cmd_status
}

cmd_off() {
  log "off"
  systemctl disable --now $TIMER 2>/dev/null || true
  bench_in "execute konsol.demo_mode.end_sessions" | tail -1
  bench_in "set-config demo_user ''"
  docker exec "$BACKEND" python3 - "$SITE_DIR/site_config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c.pop("demo_user", None); json.dump(c, open(p, "w"), indent=1)
PY
  bench_in "clear-cache"
  cmd_status
}

cmd_reset() {
  need_golden
  local t0; t0=$(date +%s)
  log "reset: begin"
  # The web tier goes down for the restore: Caddy answers with the maintenance page
  # (docker/demo/Caddyfile.demo-ext handle_errors) until the backend is back.
  $DC stop frappe_backend frappe_worker frappe_scheduler >/dev/null
  # One-off container over the same volumes; mariadb and redis keep running.
  DB_ROOT_PASSWORD=$(grep -E '^DB_ROOT_PASSWORD=' "$EXT_DIR/.env" | cut -d= -f2-)
  $DC run --rm --no-deps -v "$GOLDEN:/golden:ro" frappe_backend bash -lc \
    "cd $BENCH_DIR && bench --site $SITE --force restore /golden/database.sql.gz \
       --with-private-files /golden/private-files.tar --with-public-files /golden/public-files.tar \
       --db-root-password '$DB_ROOT_PASSWORD'" 2>&1 | grep -vE "RuntimeWarning|^\s*$" | tail -3 | tee -a "$LOG"
  $DC start frappe_backend frappe_worker frappe_scheduler >/dev/null
  for _ in $(seq 1 60); do docker exec "$BACKEND" curl -sf -o /dev/null http://localhost:8000/api/method/ping 2>/dev/null && break; sleep 2; done
  bench_in "clear-cache"
  bench_in "execute frappe.sessions.clear_all_sessions" >/dev/null
  # Warehouse: reference tables from Frappe, submitted trial balances re-landed, visitor batches dropped.
  bench_in "execute konsol.clickhouse.reconcile_all" | tail -1 | tee -a "$LOG"
  bench_in "execute konsol.consolidation.doctype.trial_balance_submission.trial_balance_submission.reland_submitted --kwargs '{\"apply\":1,\"remove_orphans\":1}'" | tail -1 | tee -a "$LOG"
  $DC --profile setup run --rm dbt_init build --profiles-dir /home/frappe/dbt_project --project-dir /home/frappe/dbt_project 2>&1 \
    | grep -E "Done\.|Completed with|ERROR creating" | tail -2 | tee -a "$LOG"
  log "reset done in $(( $(date +%s) - t0 ))s"
}

install_timer() {
  local here; here=$(cd "$(dirname "$0")" && pwd)
  install -m 644 "$here/konsolidat-demo-reset.service" /etc/systemd/system/
  install -m 644 "$here/konsolidat-demo-reset.timer" /etc/systemd/system/
  systemctl daemon-reload
}

case "${1:-}" in
  status) cmd_status ;;
  snapshot) cmd_snapshot ;;
  on) cmd_on ;;
  off) cmd_off ;;
  reset) cmd_reset ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
