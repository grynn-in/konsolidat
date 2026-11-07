# Public demo (demo mode) on the second stack

The second stack (`konsolidat-ext`, https://demo-ext.konsolidat.com) is an independent copy of the
product on the demo server, next to the live demo. It carries the fictional **aquila-bike** group
(`excel/onboarding/examples/aquila-bike`) and can be opened to the public as a trial that anyone
can use without an account and that returns to its starting point every hour.

Decided 7 Nov 2026 by Deepak Pai: on main, behind one site_config key; demo user roles EPM
Analyst + Entity Accountant (visitors can upload trial balances, run builds, prepare and approve
journals, read every report; they cannot change the chart, entities, users, settings or the close
policy); hourly reset from a golden snapshot. Rejected: a demo-only branch, a read-only demo user.

## Parts

| where | what |
|---|---|
| konsol `konsol/demo_mode.py` | reads site_config `demo_user`; `/api/method/konsol.demo_mode.try_demo` logs the visitor in as that user and lands on `/desk`; `/try` is the one-button page; `end_sessions()` for the off switch. Refuses when the key is absent, the user is missing or disabled, or holds Administrator / System Manager / EPM Admin. Nothing else in konsol knows about demo mode. |
| `demo.sh` | `status`, `snapshot`, `on`, `off`, `reset` (see the header of the script) |
| `konsolidat-demo-reset.{service,timer}` | systemd timer, hourly, installed by `demo.sh on` |
| `Caddyfile.demo-ext` | the vhost block appended to the live stack's Caddyfile, with the maintenance page shown while a reset runs |
| `docker-compose.ext.yml` | the override that makes the second stack (container names, network 172.31.0.0/24, caddy/cubejs/backup under profiles) |

## The second stack

```
/root/konsolidat-ext/            copy of the deploy checkout's compose files, .env, clickhouse/, cube/, docker/, dbt_project/
  .env                           COMPOSE_PROJECT_NAME=konsolidat-ext, SITE_NAME=SITE_DOMAIN=demo-ext.konsolidat.com,
                                 FRAPPE_PORT=172.30.0.1:8169, CLICKHOUSE_*_PORT 8223/9100, EXCEL_ODBC_PORT 15433, own passwords
  .credentials                   Administrator, MariaDB root, ClickHouse, frappectl API key (0600; never print it)
  golden/                        the golden copy demo.sh snapshot writes (database.sql.gz, private-files.tar, public-files.tar)
  demo/                          this folder, copied from the repo
  reset.log                      one line per step of every reset
```

```
cd /root/konsolidat-ext
docker compose -p konsolidat-ext --env-file .env -f docker-compose.yml -f docker-compose.ext.yml up -d --no-build
```

The image is a tag of the live one (`konsolidat-frappe:latest` → `konsolidat-ext-frappe:latest`). Never run
`deploy.sh` here; never build here. A konsol change reaches this stack with `docker cp` into
`konsolidat-ext_backend` and `konsolidat-ext_worker` followed by `docker restart konsolidat-ext_worker`.

DNS: Route 53 A record `demo-ext.konsolidat.com → 178.105.252.186`. TLS: the live Caddy obtains the
certificate once the vhost block is in its Caddyfile.

## Switching the demo on

1. Load the example (`excel/onboarding`, `konsol_load.py` against `https://demo-ext.konsolidat.com`),
   approve the Build Approvals, confirm the build is green.
2. Create the demo user: `demo@konsolidat.com`, System User, roles EPM Analyst and Entity
   Accountant, no API key, a long random password nobody keeps.
3. `demo.sh snapshot` — the golden copy is what every reset returns to. Take it with the demo OFF: with it
   on, the command refuses (visitors' uploads, journals and sessions would be frozen into the starting
   point); `--force` overrides. A failed backup never destroys the previous copy (`golden.prev` keeps the one
   before).
4. `demo.sh on` — sets `demo_user`, clears the cache, reloads the gunicorn workers (Frappe v16 caches
   site_config per worker), starts the hourly timer.
5. Check: `curl -sI https://demo-ext.konsolidat.com/try` is 200; a browser at `/try` → "Try the demo" → Desk as the demo user.

`demo.sh off` removes the key (the endpoint and `/try` answer 404 again), ends the demo user's
sessions and stops the timer. `demo.sh status` shows all of it.

## What a reset does (about two minutes, at the top of every hour)

1. Stops the web tier (backend, worker, scheduler): Caddy shows the maintenance page.
2. Removes visitors' uploaded files (a restore untars over the folders and deletes nothing; a public file
   would otherwise stay reachable by URL forever) and restores the golden database and files in a one-off
   container over the same volumes. The MariaDB root password is read by bench from `root_password` in
   `common_site_config.json` (written once from `.env` through stdin), never from a command line.
3. Starts the web tier, clears the Redis cache and every session.
4. Warehouse: `konsol.clickhouse.reconcile_all` (reference tables from Frappe), then
   `reland_submitted(apply=1, remove_orphans=1)` (every submitted trial balance landed again,
   visitor batches dropped), then a `dbt build` through the stack's `dbt_init` service.

The golden copy is replaced only by `demo.sh snapshot`, never by the timer.

Failure policy: the restore is tried twice; if it still fails the web tier stays stopped (Caddy keeps
answering 503 with the maintenance page, which is honest; a half-restored site answering 500s would not be),
`reset FAILED at step …` is logged to `reset.log` and shown by `demo.sh status`, and the next hour or a manual
`demo.sh reset` tries again. One `demo.sh` runs at a time (`flock` on `/run/lock/konsolidat-demo.lock`), and
`on`, `off` and `snapshot` refuse while the reset service is active.

## The live Caddyfile is locally modified

The vhost block lives in `/root/konsolidat/docker/caddy/Caddyfile`, a tracked file of the live deploy
checkout, so that checkout carries a local change (`git status` there shows it; the pre-edit copies are
`Caddyfile.bak-20261107*` beside it). A `git pull` that touches the Caddyfile will stop on it, and a
`git checkout -- .` would drop the block and darken demo-ext (the certificate survives in `caddy_data`).
After any redeploy: re-append `Caddyfile.demo-ext` and `caddy reload`. The clean fix is an
`import /etc/caddy/sites/*.caddy` line in the repo's Caddyfile plus a read-only bind mount of a sites folder
in the live compose file; that changes the live stack and is a decision for Deepak.

## Removing the second stack

`demo.sh off`; `systemctl disable --now konsolidat-demo-reset.timer; rm /etc/systemd/system/konsolidat-demo-reset.*;
systemctl daemon-reload`; delete the vhost block from the live Caddyfile and reload Caddy; then
`docker compose -p konsolidat-ext ... down -v` and remove `/root/konsolidat-ext`.
