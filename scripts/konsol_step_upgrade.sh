#!/bin/bash
# =============================================================================
# konsol_step_upgrade.sh — incremental (step-by-step) konsol app upgrade
#
# Drives `bench migrate` through konsol's historical waypoints INSIDE the
# running backend container, one commit at a time, so each migration patch runs
# against the schema state it was authored for (instead of a single huge leap
# that runs every patch at once against a schema that skipped all intermediate
# states).
#
# Subcommands:
#   prep                 Load full konsol git history into the container app +
#                        take a rollback DB snapshot.
#   state                Print current schema/data state (HEAD, doctypes,
#                        budgets, patch log, workspace).
#   snap   <tag>         Dump the site DB to /tmp/ck_<tag>.sql.gz (rollback point).
#   restore <tag>        Restore the site DB from /tmp/ck_<tag>.sql.gz.
#   step   <commit> [--prime-status]
#                        Optionally pre-create the Dimension/Measure `status`
#                        column (unblock for the pre-sync backfill patch),
#                        checkout <commit> in the container app, run migrate,
#                        then print state.
# =============================================================================
set -uo pipefail

SVC=frappe_backend
SITE="${SITE_NAME:-konsolidat.local}"
APP=apps/konsol
DB_ROOT="${DB_ROOT_PASSWORD:-rootpassword}"

bx() { docker compose exec -T "$SVC" bash -lc "$1"; }   # run bash in container
# SQL via stdin so backticks/identifiers are never parsed by a shell
mysql_site() { printf '%s\n' "$1" | docker compose exec -T "$SVC" bench --site "$SITE" mariadb -N 2>/dev/null; }
site_cfg() { bx "grep -oP '\"$1\": *\"\\K[^\"]+' sites/$SITE/site_config.json"; }

cmd_prep() {
  echo "== prep: loading full konsol history into container app =="
  tar czf /tmp/konsol-git.tgz -C docker/frappe/konsol .git
  docker compose cp /tmp/konsol-git.tgz "$SVC":/tmp/konsol-git.tgz
  bx "cd $APP && rm -rf .git && tar xzf /tmp/konsol-git.tgz && git checkout -f 0e18310 >/dev/null 2>&1; echo HEAD=\$(git rev-parse --short HEAD); echo commits=\$(git rev-list --count HEAD)"
  cmd_snap baseline
}

cmd_snap() {
  local tag="${1:?usage: snap <tag>}"
  local dbn dbp; dbn=$(site_cfg db_name | tr -d '\r\n '); dbp=$(site_cfg db_password | tr -d '\r\n ')
  echo "== snapshot DB ($dbn) -> /tmp/ck_${tag}.sql.gz =="
  bx "mysqldump -u $dbn -p'$dbp' -h \$DB_HOST --single-transaction $dbn > /tmp/ck_${tag}.sql 2>/tmp/dumperr && gzip -f /tmp/ck_${tag}.sql && ls -la /tmp/ck_${tag}.sql.gz || { echo WARN snapshot failed; tail -2 /tmp/dumperr; }"
}

cmd_restore() {
  local tag="${1:?usage: restore <tag>}"
  local dbn dbp; dbn=$(site_cfg db_name | tr -d '\r\n '); dbp=$(site_cfg db_password | tr -d '\r\n ')
  echo "== restore DB ($dbn) from /tmp/ck_${tag}.sql.gz =="
  bx "gunzip -c /tmp/ck_${tag}.sql.gz | mysql -u $dbn -p'$dbp' -h \$DB_HOST $dbn && echo restored"
}

cmd_state() {
  echo "----- STATE -----"
  bx "cd $APP && echo HEAD=\$(git rev-parse --short HEAD 2>/dev/null) \$(git log -1 --format=%s 2>/dev/null | cut -c1-50)"
  echo "doctypes(konsol): $(mysql_site "SELECT COUNT(*) FROM tabDocType WHERE module IN ('Pipeline','EPM','Consolidation','Allocation','Budget','Data Pipeline','EPM Registry')")"
  for dt in 'Dataset' 'Budget Cycle' 'Budget Sheet' 'Reporting Hierarchy'; do
    printf "  exists[%s]=%s\n" "$dt" "$(mysql_site "SELECT COUNT(*) FROM tabDocType WHERE name='$dt'")"
  done
  # Budget Input was retired (doctype + tables dropped, PRD-08); 0 leftover tables = healthy.
  echo "Budget Input:       retired (PRD-08); leftover tables: $(mysql_site "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN ('tabBudget Input','tabBudget Input Child')")"
  echo "Budget Sheet rows:  $(mysql_site "SELECT COUNT(*) FROM \`tabBudget Sheet\`" 2>/dev/null)"
  echo "status col(Dim):    $(mysql_site "SELECT COUNT(*) FROM information_schema.columns WHERE table_name='tabDimension' AND column_name='status'")"
  echo "patches logged:     $(mysql_site "SELECT GROUP_CONCAT(SUBSTRING_INDEX(patch,'.',-1)) FROM \`tabPatch Log\` WHERE patch LIKE 'konsol.patches%'")"
  echo "Konsolidat WS:      $(mysql_site "SELECT COUNT(*) FROM tabWorkspace WHERE name='Konsolidat'")"
  echo "-----------------"
}

cmd_step() {
  local commit="${1:?usage: step <commit> [--prime-status]}"; shift || true
  local prime=0; [ "${1:-}" = "--prime-status" ] && prime=1
  echo "############ STEP -> $commit (prime-status=$prime) ############"
  cmd_snap "pre_$commit"
  if [ "$prime" = "1" ]; then
    echo "== priming Dimension/Measure.status column =="
    mysql_site "ALTER TABLE \`tabDimension\` ADD COLUMN IF NOT EXISTS \`status\` varchar(140) DEFAULT 'Draft'"
    mysql_site "ALTER TABLE \`tabMeasure\`   ADD COLUMN IF NOT EXISTS \`status\` varchar(140) DEFAULT 'Draft'"
  fi
  echo "== checkout $commit =="
  bx "cd $APP && git checkout -f $commit >/dev/null 2>&1 && echo now=\$(git rev-parse --short HEAD)"
  echo "== bench migrate =="
  if bx "bench --site $SITE migrate" > "/tmp/migrate_${commit}.log" 2>&1; then
    echo "migrate OK"
  else
    echo "!! migrate FAILED (exit) — tail:"; tail -25 "/tmp/migrate_${commit}.log"
  fi
  cmd_state
}

cmd_reconcile() {
  # After a multi-hop upgrade, some doctypes can end up with a DB table but NO
  # tabDocType metadata record (partial migrates / reload-doc during hops, then
  # bench migrate's sync cache skips re-importing). That makes any code reading
  # the doctype meta fail with DoesNotExistError. Force-reimport every konsol
  # doctype from its JSON to reconcile table<->metadata. Idempotent.
  echo "== reconcile: reload-doc every konsol doctype from JSON =="
  bx 'cd /home/frappe/frappe-bench
ok=0; fail=0
for j in $(find apps/konsol/konsol -path "*/doctype/*/*.json" | grep -vE "/test|dashboard|_dashboard"); do
  dir=$(basename "$(dirname "$j")")
  mod=$(echo "$j" | sed -E "s|apps/konsol/konsol/([^/]+)/doctype/.*|\1|")
  if bench --site '"$SITE"' reload-doc "$mod" doctype "$dir" >/dev/null 2>&1; then ok=$((ok+1)); else fail=$((fail+1)); echo "  FAIL: $mod/$dir"; fi
done
echo "reloaded ok=$ok fail=$fail"
bench --site '"$SITE"' clear-cache >/dev/null 2>&1 && echo cache-cleared'
}

case "${1:-}" in
  prep)      cmd_prep ;;
  state)     cmd_state ;;
  snap)      cmd_snap "${2:-}";;
  restore)   cmd_restore "${2:-}";;
  step)      shift; cmd_step "$@";;
  reconcile) cmd_reconcile ;;
  *) echo "usage: $0 {prep|state|snap <tag>|restore <tag>|step <commit> [--prime-status]|reconcile}"; exit 1;;
esac
