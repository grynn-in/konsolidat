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
# Frappe v16 caches site_config per gunicorn worker while it serves requests, so a changed demo_user key is
# seen by some workers and not others until they reload. HUP to the gunicorn master replaces the workers
# gracefully (no dropped requests, no downtime); the first live off/on cycle showed one worker still logging in.
reload_web() {
  local pid
  pid=$(docker exec "$BACKEND" bash -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *gunicorn*) if [ "$(awk "/^PPid/{print \$2}" $p/status)" = 1 ]; then echo ${p#/proc/}; fi;; esac; done' | head -1)
  if [ -n "$pid" ]; then docker exec "$BACKEND" kill -HUP "$pid"; sleep 3; else log "gunicorn master not found; restarting the backend"; docker restart "$BACKEND" >/dev/null; fi
}
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
  # normalise names: one database, one private, one public archive ("*-files.tar" also matches the
  # private archive, so the public one is picked by exclusion; the first live run lost it that way)
  (
    cd "$GOLDEN"
    for f in *-database.sql.gz; do [ -e "$f" ] && mv "$f" database.sql.gz; done
    for f in *-private-files.tar; do [ -e "$f" ] && mv "$f" private-files.tar; done
    for f in *-files.tar; do case "$f" in *private*) ;; *) [ -e "$f" ] && mv "$f" public-files.tar ;; esac; done
    true
  )
  [ -f "$GOLDEN/database.sql.gz" ] || { echo "snapshot produced no database archive" >&2; exit 2; }
  docker exec "$BACKEND" rm -rf "$SITE_DIR/private/backups/golden"
  ls -la "$GOLDEN"
  log "snapshot done"
}

cmd_on() {
  log "on: demo_user=$DEMO_USER"
  bench_in "set-config demo_user $DEMO_USER"
  bench_in "clear-cache"
  # a visitor who hit /try while the demo was off left a cached 404 for that URL (frappe.cache website_404);
  # clear-cache alone did not drop it on the first live run
  bench_in "execute frappe.website.utils.clear_website_cache" >/dev/null
  reload_web
  install_timer
  systemctl enable --now $TIMER
  cmd_status
}

cmd_off() {
  log "off"
  systemctl disable --now $TIMER 2>/dev/null || true
  bench_in "execute konsol.demo_mode.end_sessions" | tail -1
  bench_in "set-config demo_user ''"
  # set-config cannot remove a key; drop it from the file (docker exec needs -i to read the heredoc)
  docker exec -i "$BACKEND" python3 - "$SITE_DIR/site_config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c.pop("demo_user", None); json.dump(c, open(p, "w"), indent=1)
PY
  bench_in "clear-cache"
  bench_in "execute frappe.website.utils.clear_website_cache" >/dev/null
  reload_web
  cmd_status
}

cmd_reset() {
  need_golden
  local t0; t0=$(date +%s)
  log "reset: begin"
  # The web tier goes down for the restore: Caddy answers with the maintenance page
  # (docker/demo/Caddyfile.demo-ext handle_errors) until the backend is back.
  # Whatever happens below, the web tier comes back: a failed restore must not leave the site down.
  trap 'log "reset FAILED at line $LINENO; starting the web tier"; $DC start frappe_backend frappe_worker frappe_scheduler >/dev/null 2>&1 || true' ERR
  $DC stop frappe_backend frappe_worker frappe_scheduler >/dev/null
  # One-off container over the same volumes; mariadb and redis keep running. The image's entrypoint only
  # knows web|worker|scheduler, hence --entrypoint. Only the archives that exist are restored.
  local files=""
  [ -f "$GOLDEN/private-files.tar" ] && files="$files --with-private-files /golden/private-files.tar"
  [ -f "$GOLDEN/public-files.tar" ] && files="$files --with-public-files /golden/public-files.tar"
  DB_ROOT_PASSWORD=$(grep -E '^DB_ROOT_PASSWORD=' "$EXT_DIR/.env" | cut -d= -f2-)
  $DC run --rm --no-deps --entrypoint bash -v "$GOLDEN:/golden:ro" frappe_backend -lc \
    "cd $BENCH_DIR && bench --site $SITE --force restore /golden/database.sql.gz $files \
       --db-root-password '$DB_ROOT_PASSWORD'" 2>&1 | grep -vE "RuntimeWarning|^\s*$" | tail -3 | tee -a "$LOG"
  $DC start frappe_backend frappe_worker frappe_scheduler >/dev/null
  trap - ERR
  for _ in $(seq 1 60); do curl -sf -o /dev/null "https://$SITE/api/method/ping" 2>/dev/null && break; sleep 2; done
  bench_in "clear-cache"
  bench_in "execute frappe.sessions.clear_all_sessions" >/dev/null
  # Warehouse: reference tables from Frappe, submitted trial balances re-landed, visitor batches dropped.
  bench_in "execute konsol.clickhouse.reconcile_all" | tail -1 | tee -a "$LOG"
  # run_reland is the job reland_submitted(apply=1) would queue; called directly it runs to completion here,
  # so the dbt build below never starts before the visitor batches are gone
  bench_in "execute konsol.consolidation.doctype.trial_balance_submission.trial_balance_submission.run_reland --kwargs '{\"remove_orphans\":1}'" | tail -1 | tee -a "$LOG"
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
