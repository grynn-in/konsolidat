# Public demo mode

A site can be opened as a public trial. A visitor opens `/try`, is logged in as one demo user, and the site returns to a golden snapshot on a timer. Decided 7 Nov 2026 by Deepak Pai: on main, behind one site_config key; the demo user holds EPM Analyst and Entity Accountant (visitors can upload trial balances, run builds, prepare and approve journals, and read every report; they cannot change the chart, entities, users, settings or the close policy); hourly reset from a golden snapshot. Rejected: a demo-only branch, a read-only demo user.

The trial is loaded with the **aquila-bike** example (`excel/onboarding/examples/aquila-bike`). Host names, addresses and credentials are not in this repo.

## Parts

| where | what |
|---|---|
| konsol `konsol/demo_mode.py` | reads site_config `demo_user`; `/api/method/konsol.demo_mode.try_demo` logs the visitor in as that user and lands on `/desk`; `/try` is the one-button page; `end_sessions()` for the off switch. Refuses when the key is absent, the user is missing or disabled, or holds Administrator / System Manager / EPM Admin. Nothing else in konsol knows about demo mode. |
| `demo.sh` | `status`, `snapshot`, `on`, `off`, `reset`. `EXT_DIR` and `SITE` come from the environment. |
| `konsolidat-demo-reset.{service,timer}` | systemd timer, hourly, installed by `demo.sh on` |
| `Caddyfile.demo-ext` | vhost template. `DEMO_SITE` and `UPSTREAM` come from the Caddy process environment. Shows a maintenance page while a reset runs. |
| `docker-compose.ext.yml` | compose override so a second project can run beside another: its own container names and network; caddy and backup stay under profiles |

## Switching the demo on

1. Load aquila-bike (`excel/onboarding`, `konsol_load.py`), approve the Build Approvals, confirm the build is green.
2. Create the demo user: System User, roles EPM Analyst and Entity Accountant, no API key, a long random password nobody keeps.
3. `demo.sh snapshot` — the golden copy is what every reset returns to. Take it with the demo OFF: with it on, the command refuses (visitors' uploads, journals and sessions would be frozen into the starting point); `--force` overrides. A failed backup never destroys the previous copy (`golden.prev` keeps the one before).
4. `demo.sh on` — refuses without a golden copy; re-enables the demo user (`konsol.demo_mode.switch_on`), sets `demo_user`, clears the cache, reloads the gunicorn workers (Frappe v16 caches site_config per worker), starts the hourly timer. `demo.sh off` first runs `konsol.demo_mode.switch_off` (user disabled, every session ended), which every worker sees at once, then drops the key.
5. Check: `GET /try` is 200; the button logs in as the demo user and lands on Desk.

`demo.sh off` removes the key (the endpoint and `/try` answer 404 again), ends the demo user's sessions and stops the timer. `demo.sh status` shows all of it.

## What a reset does (about two minutes, at the top of every hour)

1. Stops the web tier (backend, worker, scheduler). The vhost shows the maintenance page.
2. Removes visitors' uploaded files (a restore untars over the folders and deletes nothing; a public file would otherwise stay reachable by URL) and restores the golden database and files in a one-off container over the same volumes. The MariaDB root password is read by bench from `root_password` in `common_site_config.json` (written once from `.env` through stdin), never from a command line.
3. Starts the web tier, clears the Redis cache and every session.
4. Warehouse: `konsol.clickhouse.reconcile_all` (reference tables from Frappe), then `reland_submitted(apply=1, remove_orphans=1)` (every submitted trial balance landed again, visitor batches dropped), then a `dbt build` through the project's `dbt_init` service.

The golden copy is replaced only by `demo.sh snapshot`, never by the timer.

Failure policy: the restore is tried twice; if it fails at the stop or restore step the web tier stays stopped (the vhost keeps answering 503 with the maintenance page); a failure in a later step (cache, reconcile, re-land, dbt) leaves the site running on the restored database with a possibly stale warehouse. Either way `reset FAILED at step …` is logged to `reset.log` and shown by `demo.sh status`, and the next hour or a manual `demo.sh reset` tries again. One state-changing `demo.sh` runs at a time (`flock` on `/run/lock/konsolidat-demo.lock`); `status` never takes the lock; `on`, `off` and `snapshot` refuse while the reset service is active.

## Removing demo mode

`demo.sh off`, then disable and remove the `konsolidat-demo-reset` timer and service. Drop the vhost. Tear the compose project down only when the trial itself is finished.
