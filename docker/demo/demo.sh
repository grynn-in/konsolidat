#!/bin/bash
# demo.sh — switch the public trial ("demo mode") of the second stack on or off,
# take its golden snapshot, and reset it to that snapshot.
#
#   demo.sh status              what is on, when the last reset ran (or failed), how old the golden copy is
#   demo.sh snapshot [--force]  take the golden copy of the site as it is NOW (deliberate, never automatic;
#                               refuses while demo mode is on unless --force: visitors' data would be frozen in)
#   demo.sh on                  set demo_user in site_config, reload the web workers, start the hourly reset timer
#   demo.sh off                 remove demo_user, end the demo user's sessions, reload, stop the timer
#   demo.sh reset               restore the golden copy (database + files), resync the warehouse, dbt build
#
# Decided 7 Nov 2026 by Deepak Pai: the demo is switchable, resets hourly, the demo user holds
# EPM Analyst + Entity Accountant. konsol reads exactly one key, site_config `demo_user`
# (konsol/demo_mode.py); everything else lives here. Runs as root on the demo server.
# Never touches the live stack (/root/konsolidat, containers konsolidat_*).
#
# Failure policy of `reset`: the restore is tried twice; if it still fails the web tier stays STOPPED
# (Caddy answers 503 with the maintenance page; a half-restored site answering 500s would be worse),
# `reset FAILED` is logged and shown by `status`, and the next hour (or a manual `reset`) tries again.
set -euo pipefail

EXT_DIR=${EXT_DIR:-/root/konsolidat-ext}
SITE=${SITE:-demo-ext.konsolidat.com}
DEMO_USER=${DEMO_USER:-demo@konsolidat.com}
GOLDEN=$EXT_DIR/golden
LOG=$EXT_DIR/reset.log
LOCK=/run/lock/konsolidat-demo.lock
TIMER=konsolidat-demo-reset.timer
SERVICE=konsolidat-demo-reset.service
BACKEND=konsolidat-ext_backend
BENCH_DIR=/home/frappe/frappe-bench
SITE_DIR=$BENCH_DIR/sites/$SITE
DC="docker compose -p konsolidat-ext --env-file $EXT_DIR/.env -f $EXT_DIR/docker-compose.yml -f $EXT_DIR/docker-compose.ext.yml"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$LOG"; }
# bench_in: a bench command whose failure is tolerated (status, cache); bench_run: one whose failure matters.
bench_in() { docker exec "$BACKEND" bash -lc "cd $BENCH_DIR && bench --site $SITE $*" 2>&1 | grep -v RuntimeWarning || true; }
bench_run() {
  local out rc
  out=$(docker exec "$BACKEND" bash -lc "cd $BENCH_DIR && bench --site $SITE $*" 2>&1); rc=$?
  printf '%s\n' "$out" | grep -v RuntimeWarning | tail -3
  return $rc
}
need_golden() { [ -f "$GOLDEN/database.sql.gz" ] || { echo "no golden copy in $GOLDEN: run 'demo.sh snapshot' first" >&2; exit 2; }; }
demo_user_now() { docker exec "$BACKEND" python3 -c "import json;print(json.load(open('$SITE_DIR/site_config.json')).get('demo_user') or '')" 2>/dev/null || echo "?"; }
reset_running() { systemctl is-active --quiet "$SERVICE"; }

# Frappe v16 caches site_config per gunicorn worker while it serves requests, so a changed demo_user key is
# seen by some workers and not others until they reload. HUP to the gunicorn MASTER replaces the workers
# gracefully. The master is the gunicorn process whose parent is not gunicorn (a worker HUPped alone would
# just die and be respawned stale). `kill` is a bash builtin in the image, not a binary.
reload_web() {
  local pid
  pid=$(docker exec "$BACKEND" bash -c '
    for p in /proc/[0-9]*; do
      c=$(tr "\0" " " < "$p/cmdline" 2>/dev/null) || continue
      case "$c" in *bin/gunicorn*) ;; *) continue;; esac
      pp=$(awk "/^PPid/{print \$2}" "$p/status"); pc=$(tr "\0" " " < "/proc/$pp/cmdline" 2>/dev/null || true)
      case "$pc" in *bin/gunicorn*) ;; *) echo "${p#/proc/}";; esac
    done' | head -1)
  if [ -n "$pid" ]; then docker exec "$BACKEND" bash -c "kill -HUP $pid"; sleep 3; else log "gunicorn master not found; restarting the backend"; docker restart "$BACKEND" >/dev/null; fi
}

# MariaDB root password for bench restore: kept in common_site_config.json (`root_password`, the key
# frappe's get_root_connection falls back to) inside the sites volume, written once from .env through
# stdin, so it never appears on a command line, in `ps` or in `docker inspect`.
ensure_root_password() {
  docker exec -i "$BACKEND" python3 - "$BENCH_DIR/sites/common_site_config.json" <<PY
import json, sys
p = sys.argv[1]; c = json.load(open(p))
pw = """$(grep -E '^DB_ROOT_PASSWORD=' "$EXT_DIR/.env" | cut -d= -f2- | sed -e "s/^['\"]//" -e "s/['\"]\$//")"""
if pw and c.get("root_password") != pw:
    c["root_password"] = pw; json.dump(c, open(p, "w"), indent=1); print("root_password written to common_site_config.json")
PY
}

cmd_status() {
  local du; du=$(demo_user_now)
  echo "site:        $SITE"
  echo "demo_user:   ${du:-(off)}"
  echo "timer:       $(systemctl is-enabled $TIMER 2>/dev/null || echo not-installed) / $(systemctl is-active $TIMER 2>/dev/null || echo inactive)"
  systemctl list-timers --no-pager "$TIMER" 2>/dev/null | sed -n 2p | sed 's/^/             /' || true
  echo "reset job:   $(systemctl is-active $SERVICE 2>/dev/null || echo inactive)"
  if [ -f "$GOLDEN/database.sql.gz" ]; then echo "golden:      $(date -u -r "$GOLDEN/database.sql.gz" +%FT%TZ) ($(du -sh "$GOLDEN" | cut -f1))"; else echo "golden:      none"; fi
  echo "last reset:  $(grep -hE 'reset (done|FAILED)' "$LOG" 2>/dev/null | tail -1 || echo never)"
}

cmd_snapshot() {
  # The golden copy is what every reset returns to. Taking it is a decision, so it is a command, not a
  # timer: check the site first (data loaded, builds green, demo user present), and take it with the demo OFF.
  local du; du=$(demo_user_now)
  if [ -n "$du" ] && [ "$du" != "?" ] && [ "${1:-}" != "--force" ]; then
    echo "demo mode is ON (demo_user=$du): a snapshot now freezes visitors' uploads, journals and sessions into the" >&2
    echo "starting point. Run 'demo.sh off' first, or 'demo.sh snapshot --force' if that is what you want." >&2
    exit 3
  fi
  if reset_running; then echo "a reset is running; try again in a few minutes" >&2; exit 3; fi
  log "snapshot: backing up $SITE with files (demo_user='${du}')"
  docker exec "$BACKEND" rm -rf "$SITE_DIR/private/backups/golden"
  bench_run "backup --with-files --backup-path $SITE_DIR/private/backups/golden"
  # build the new copy beside the old one; replace only when it is complete (an old copy is never lost to a
  # failed backup)
  rm -rf "$GOLDEN.new"; mkdir -p "$GOLDEN.new"
  docker cp "$BACKEND:$SITE_DIR/private/backups/golden/." "$GOLDEN.new/"
  docker exec "$BACKEND" rm -rf "$SITE_DIR/private/backups/golden"
  (
    cd "$GOLDEN.new"
    for f in *-database.sql.gz; do [ -e "$f" ] && mv "$f" database.sql.gz; done
    for f in *-private-files.tar; do [ -e "$f" ] && mv "$f" private-files.tar; done
    # "*-files.tar" also matches the private archive: the public one is picked by exclusion
    for f in *-files.tar; do case "$f" in *private*) ;; *) [ -e "$f" ] && mv "$f" public-files.tar ;; esac; done
    rm -f ./*-site_config_backup.json
    true
  )
  [ -f "$GOLDEN.new/database.sql.gz" ] || { log "snapshot FAILED: no database archive; the old golden copy is untouched"; rm -rf "$GOLDEN.new"; exit 2; }
  rm -rf "$GOLDEN.prev"; [ -d "$GOLDEN" ] && mv "$GOLDEN" "$GOLDEN.prev"; mv "$GOLDEN.new" "$GOLDEN"
  ls -la "$GOLDEN"
  log "snapshot done"
}

install_timer() {
  local here; here=$(cd "$(dirname "$0")" && pwd)
  install -m 644 "$here/$SERVICE" /etc/systemd/system/
  install -m 644 "$here/$TIMER" /etc/systemd/system/
  systemctl daemon-reload
}

cmd_on() {
  if reset_running; then echo "a reset is running; try again in a few minutes" >&2; exit 3; fi
  need_golden
  log "on: demo_user=$DEMO_USER"
  bench_run "set-config demo_user $DEMO_USER" >/dev/null
  # re-enable the demo user (off disables it, which every worker sees at once, unlike the cached key)
  bench_run "execute konsol.demo_mode.switch_on" | tail -1
  bench_in "clear-cache" >/dev/null
  # a visitor who hit /try while the demo was off left a cached 404 for that URL (frappe.cache website_404),
  # which clear-cache alone did not drop on the first live run
  bench_in "execute frappe.website.utils.clear_website_cache" >/dev/null
  reload_web
  install_timer
  systemctl enable "$TIMER" >/dev/null 2>&1
  systemctl restart "$TIMER"      # enable --now would not re-read an edited OnCalendar on an active timer
  cmd_status
}

cmd_off() {
  if reset_running; then echo "a reset is running; try again in a few minutes" >&2; exit 3; fi
  log "off"
  systemctl disable --now "$TIMER" >/dev/null 2>&1 || true
  # first disable the demo user and end every session (konsol.demo_mode.switch_off): decide() reads the User
  # row on every request, so this closes the door before the cached key has expired on every worker
  bench_run "execute konsol.demo_mode.switch_off" | tail -1
  # set-config cannot remove a key; drop it from the file (docker exec needs -i to read the heredoc)
  docker exec -i "$BACKEND" python3 - "$SITE_DIR/site_config.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c.pop("demo_user", None); json.dump(c, open(p, "w"), indent=1)
PY
  bench_in "clear-cache" >/dev/null
  bench_in "execute frappe.website.utils.clear_website_cache" >/dev/null
  reload_web
  cmd_status
}

restore_once() {
  # One-off container over the same volumes; mariadb and redis keep running. The image's entrypoint only
  # knows web|worker|scheduler, hence --entrypoint. bench restore untars the archives OVER the files folders
  # and deletes nothing, so visitors' uploads are removed first (a public file would otherwise stay reachable
  # by URL forever). Only the archives that exist are restored.
  local files=""
  [ -f "$GOLDEN/private-files.tar" ] && files="$files --with-private-files /golden/private-files.tar"
  [ -f "$GOLDEN/public-files.tar" ] && files="$files --with-public-files /golden/public-files.tar"
  $DC run --rm --no-deps --entrypoint bash -v "$GOLDEN:/golden:ro" frappe_backend -lc \
    "cd $BENCH_DIR && rm -rf $SITE_DIR/public/files/* $SITE_DIR/private/files/* \
       && bench --site $SITE --force restore /golden/database.sql.gz $files" 2>&1 | grep -vE "RuntimeWarning|^\s*$" | tail -3 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

cmd_reset() {
  need_golden
  ensure_root_password >/dev/null
  # not `local`: the EXIT trap runs after the function has returned, where a local is unbound (set -u)
  RESET_OK=0; step="init"
  local t0
  t0=$(date +%s)
  log "reset: begin"
  # Whatever happens below (set -e, a signal from systemd's TimeoutStartSec, a failed step), the outcome is
  # logged. The web tier is restarted only after a successful restore; see the failure policy in the header.
  step="stop"
  trap 'rc=$?; if [ "${RESET_OK:-0}" != 1 ]; then log "reset FAILED at step ${step:-?} (rc=$rc); web tier left STOPPED, Caddy serves the maintenance page; next hour retries"; exit 1; fi' EXIT
  $DC stop frappe_backend frappe_worker frappe_scheduler >/dev/null
  step="restore"
  if ! restore_once; then log "restore failed once; retrying"; sleep 10; restore_once; fi
  step="start"
  $DC start frappe_backend frappe_worker frappe_scheduler >/dev/null
  for _ in $(seq 1 60); do curl -sf -o /dev/null "https://$SITE/api/method/ping" 2>/dev/null && break; sleep 2; done
  step="cache"
  bench_in "clear-cache" >/dev/null
  bench_in "execute frappe.sessions.clear_all_sessions" >/dev/null
  # Warehouse: reference tables from Frappe, submitted trial balances re-landed, visitor batches dropped.
  # run_reland is the job reland_submitted(apply=1) would queue; called directly it runs to completion here,
  # so the dbt build below never starts before the visitor batches are gone.
  step="reconcile_all"
  bench_run "execute konsol.clickhouse.reconcile_all" | tail -1 | tee -a "$LOG"
  step="run_reland"
  bench_run "execute konsol.consolidation.doctype.trial_balance_submission.trial_balance_submission.run_reland --kwargs '{\"remove_orphans\":1}'" | tail -1 | tee -a "$LOG"
  step="dbt build"
  local dbt_out
  dbt_out=$($DC --profile setup run --rm dbt_init build --profiles-dir /home/frappe/dbt_project --project-dir /home/frappe/dbt_project 2>&1) || { printf '%s\n' "$dbt_out" | tail -5 | tee -a "$LOG"; false; }
  printf '%s\n' "$dbt_out" | grep -E "Done\.|Completed with" | tail -2 | tee -a "$LOG"
  RESET_OK=1
  log "reset done in $(( $(date +%s) - t0 ))s"
}

# One demo.sh at a time: a manual `off` or `snapshot` during the timer's reset would act on a stopped
# container and leave the demo half-switched.
mkdir -p "$(dirname "$LOCK")"
exec 9>"$LOCK"
flock -n 9 || { echo "another demo.sh is running (lock $LOCK)" >&2; exit 3; }

case "${1:-}" in
  status) cmd_status ;;
  snapshot) cmd_snapshot "${2:-}" ;;
  on) cmd_on ;;
  off) cmd_off ;;
  reset) cmd_reset ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
