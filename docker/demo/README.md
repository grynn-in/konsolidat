# Public demo (demo mode) on a second stack

The second stack is an independent copy of the product, run beside an existing deployment with its own
compose project, database and warehouse. It carries the fictional **aquila-bike** group
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
| `Caddyfile.demo-ext` | the vhost block added to the proxy's Caddyfile, with the maintenance page shown while a reset runs |
| `docker-compose.ext.yml` | the override that makes the second stack (own container names and network, caddy/backup under profiles) |

## The second stack

Its working folder holds:

```
  copy of the deploy checkout's compose files, .env, clickhouse/, docker/, dbt_project/
  .env           compose project name, SITE_NAME / SITE_DOMAIN, FRAPPE_PORT, the ClickHouse and Excel ODBC
                 port variables and its own passwords, all set in `.env`
  .credentials   Administrator, MariaDB root, ClickHouse, frappectl API key (0600; never print it)
  golden/        the golden copy demo.sh snapshot writes (database.sql.gz, private-files.tar, public-files.tar)
  demo/          this folder, copied from the repo
  reset.log      one line per step of every reset
```

Start it with the base compose file plus `docker-compose.ext.yml`, `--env-file .env` and the project name
from `.env`, `up -d --no-build`.

The image is the existing deployment's image under a second tag. Never run `deploy.sh` here; never build
here. A konsol change reaches this stack with `docker cp` into its backend and worker containers followed by
a restart of the worker.

DNS and TLS: the site domain is set in `.env`; the proxy obtains the certificate once the vhost block is in
its Caddyfile.

## Switching the demo on

1. Load the example (`excel/onboarding`, `konsol_load.py` against the site),
   approve the Build Approvals, confirm the build is green.
2. Create the demo user (a System User), roles EPM Analyst and Entity
   Accountant, no API key, a long random password nobody keeps.
3. `demo.sh snapshot` — the golden copy is what every reset returns to. Take it with the demo OFF: with it
   on, the command refuses (visitors' uploads, journals and sessions would be frozen into the starting
   point); `--force` overrides. A failed backup never destroys the previous copy (`golden.prev` keeps the one
   before).
4. `demo.sh on` — refuses without a golden copy; re-enables the demo user (`konsol.demo_mode.switch_on`),
   sets `demo_user`, clears the cache, reloads the gunicorn workers (Frappe v16 caches site_config per
   worker), starts the hourly timer. `demo.sh off` first runs `konsol.demo_mode.switch_off` (user disabled,
   every session ended), which every worker sees at once, then drops the key.
5. Check: `curl -sI https://<SITE_DOMAIN>/try` is 200; a browser at `/try` → "Try the demo" → Desk as the demo user.

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

Failure policy: the restore is tried twice; if it fails at the stop or restore step the web tier stays
stopped (Caddy keeps answering 503 with the maintenance page, which is honest; a half-restored site
answering 500s would not be); a failure in a later step (cache, reconcile, re-land, dbt) leaves the site
running on the restored database with a possibly stale warehouse. Either way `reset FAILED at step …` is
logged to `reset.log` and shown by `demo.sh status`, and the next hour or a manual `demo.sh reset` tries
again (the password step runs in a one-off container, so a retry works with the web tier down). One
state-changing `demo.sh` runs at a time (`flock` on `/run/lock/konsolidat-demo.lock`); `status` never takes
the lock; `on`, `off` and `snapshot` refuse while the reset service is active.

## The proxy's Caddyfile is locally modified

The vhost block is appended to the Caddyfile of the existing deployment, a tracked file of its checkout, so
that checkout carries a local change (keep a copy of the pre-edit file). A `git pull` that touches the
Caddyfile will stop on it, and a `git checkout -- .` would drop the block. After any redeploy: re-append
`Caddyfile.demo-ext` and `caddy reload`. The clean fix is an `import /etc/caddy/sites/*.caddy` line in the
repo's Caddyfile plus a read-only bind mount of a sites folder in the compose file; that changes the
existing deployment and is a decision for Deepak.

## Removing the second stack

`demo.sh off`; disable the reset timer and remove its unit files, then `systemctl daemon-reload`; delete the
vhost block from the Caddyfile and reload Caddy; then `docker compose ... down -v` for the project and remove
its working folder.
