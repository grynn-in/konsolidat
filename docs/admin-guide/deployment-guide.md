# Deployment Guide

Deploy Konsolidat with a single command. Everything runs in Docker — no manual setup required.

## Quick Start (One-Click Deploy)

```bash
# On a fresh Ubuntu 22.04 server (Hetzner, DigitalOcean, AWS, etc.)
curl -fsSL https://get.docker.com | sh
git clone https://github.com/grynn-in/konsolidat.git
cd konsolidat
./deploy.sh
```

That's it. Open the URL printed at the end and log in.

For HTTPS with a custom domain:

```bash
./deploy.sh --domain epm.yourcompany.com
```

Caddy auto-provisions Let's Encrypt certificates.

## What deploy.sh Does

```
┌──────────────────────────────────────────────────────────────────┐
│                       ./deploy.sh                                │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  First:  Check prerequisites (Docker, Docker Compose)            │
│          Generate random passwords → .env                        │
│                                                                  │
│  Step 1: Start infrastructure                                    │
│          ┌──────────┐ ┌────────┐ ┌────────┐ ┌────────────┐      │
│          │ MariaDB  │ │ Redis  │ │ Redis  │ │ ClickHouse │      │
│          │ (Frappe  │ │ (cache)│ │(queue) │ │  (OLAP)    │      │
│          │  data)   │ │        │ │        │ │            │      │
│          └──────────┘ └────────┘ └────────┘ └────────────┘      │
│          Wait for all healthchecks ✓ ✓ ✓ ✓                      │
│                                                                  │
│  Step 2: Build Frappe + Konsol image                             │
│          (first run only — cached after that)                    │
│                                                                  │
│  Step 3: Create Frappe site + install Konsol app                 │
│          • Creates database                                      │
│          • Sets admin password                                   │
│          • Configures ClickHouse connection                      │
│                                                                  │
│  Step 4: Start application services                              │
│          ┌──────────────┐ ┌────────┐ ┌───────────┐              │
│          │Frappe Backend│ │ Worker │ │ Scheduler │              │
│          │   :8069      │ │ (jobs) │ │  (cron)   │              │
│          └──────────────┘ └────────┘ └───────────┘              │
│          ┌──────────┐ ┌──────────┐                               │
│          │ Cube.js  │ │  Caddy   │                               │
│          │ (API)    │ │(reverse  │                               │
│          │  :4000   │ │ proxy)   │                               │
│          └──────────┘ └──────────┘                               │
│                                                                  │
│  Step 5: Run dbt build                                           │
│          • Creates gold models (trial balance, P&L, etc.)        │
│          • Empty until data is loaded                            │
│                                                                  │
│  Last:   Print URLs + credentials                                │
│          ┌──────────────────────────────────────────────┐        │
│          │ ✅ Konsolidat is ready!                       │        │
│          │                                              │        │
│          │ Frappe:     http://your-ip:8069              │        │
│          │ Admin:      Administrator / xK9m2...         │        │
│          │ Cube.js:    http://your-ip:4000              │        │
│          │ Excel ODBC: your-ip:15432                    │        │
│          └──────────────────────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────┘
```

## Server Requirements

A single server runs everything:

| Provider | Plan | Specs | Monthly Cost |
|----------|------|-------|-------------|
| Hetzner | CPX41 | 8 vCPU, 16 GB RAM, 240 GB SSD | ~€15 |
| DigitalOcean | Standard 8GB | 4 vCPU, 8 GB RAM, 160 GB | ~$48 |
| AWS | t3.xlarge | 4 vCPU, 16 GB RAM, EBS | ~$120 |

**Minimum**: 4 vCPU, 8 GB RAM, 80 GB SSD, Ubuntu 22.04

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Single Server                           │
│                                                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                 Docker Compose                         │  │
│  │                                                        │  │
│  │  ┌──────────┐ ┌────────────┐ ┌──────────────────────┐  │  │
│  │  │ MariaDB  │ │  Redis x2  │ │     ClickHouse       │  │  │
│  │  │(metadata)│ │(cache+jobs)│ │  (financial data)    │  │  │
│  │  └──────────┘ └────────────┘ └──────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │           Frappe + Konsol App                     │  │  │
│  │  │  backend (web) + worker (jobs) + scheduler       │  │  │
│  │  │  • Consolidation & allocation doctypes           │  │  │
│  │  │  • ClickHouse sync hooks                         │  │  │
│  │  │  • Budget write-back API                         │  │  │
│  │  │  • Pipeline runner (dbt build)                   │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌────────────┐  ┌──────────────────────────────────┐  │  │
│  │  │  Cube.js   │  │         Caddy                    │  │  │
│  │  │ (semantic  │  │  (reverse proxy + auto-SSL)      │  │  │
│  │  │  layer)    │  │                                  │  │  │
│  │  └────────────┘  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                             │
│  Persistent volumes: mariadb_data, clickhouse_data,         │
│  frappe_sites, caddy_data (SSL certs)                       │
└─────────────────────────────────────────────────────────────┘
```

## Services

| Service | Port | Purpose |
|---------|------|---------|
| **Frappe** | 8069 | Web UI, API, doctype management |
| **Cube.js** | 4000 | Semantic layer for dashboards |
| **ClickHouse HTTP** | 8123 | Direct ClickHouse queries |
| **Excel ODBC** | 15432 | PostgreSQL wire protocol for Excel |
| **Caddy** | 80, 443 | HTTPS reverse proxy |

Internal services (not exposed): MariaDB (3306), Redis cache (6379), Redis queue (6380).

## Managing the Deployment

```bash
# Service status
./deploy.sh status

# View logs
./deploy.sh logs

# Stop everything
./deploy.sh down

# Restart after config change
docker compose restart

# Restart a single service
docker compose restart frappe_backend
```

## Connecting Excel

After deployment:

1. Open the Konsolidat Excel template (included in the repo under `excel/`)
2. Go to **Data** tab → **Get Data** → **From ODBC**
3. Connection string: `Host=your-server-ip; Port=15432; Database=epm_gold`
4. User: `default`, Password: (from `.credentials` file)

The template includes pre-built reports for Trial Balance, P&L, Balance Sheet, and Budget vs Actual.

## Loading Data

There is no demo data. A fresh ClickHouse volume gets schema only: `clickhouse/init-db.sql` and `clickhouse/raw-schema.sql` (the empty ERP landing tables dbt reads, so staging does not fail on a missing source).

Data comes from two places:

- **Connectors**: an ERP connector pulls ledger data into ClickHouse. See [Connecting Real ERP Data](#connecting-real-erp-data).
- **Trial balance uploads**: an entity without a connector uploads its trial balance as a file. A single trial balance goes through the Trial Balance Submission form in Desk. Bulk uploads (one file for many entities and periods) go through konsol-exec at `/konsol-exec/uploads`, which only the Close Lead (EPM Admin) or a System Manager can use.

To start again from an empty ClickHouse volume:

```bash
./deploy.sh down
docker volume rm open_epm_clickhouse_data
./deploy.sh
```

## Connecting Real ERP Data

To connect a D365 Finance & Operations instance:

1. Log into Frappe as Administrator: `http://your-server:8069`. Creating a Pipeline Run needs Administrator or System Manager.
2. Go to **EPM Settings**
3. Enter your D365 credentials (Tenant ID, Client ID, Client Secret, Environment URL)
4. Open a new **Pipeline Run** (`/app/pipeline-run/new`) and click **Run Pipeline** to sync data

Konsolidat supports any ERP via [Airbyte connectors](https://docs.airbyte.com/integrations/). See [D365 Integration](d365-integration.md) for detailed setup.

## Backup & Restore

### Automatic Nightly Backup

Backups are built into the deployment. Run a backup:

```bash
./deploy.sh backup
```

This backs up:

- **MariaDB** — all Frappe data (doctypes, users, config)
- **ClickHouse** — all financial data (trial balances, budgets, consolidations)
- **Frappe files** — uploads, site config

Backups are stored in `./backups/` with 7-day rotation.

### Schedule Nightly Backups

Add a cron job on the host:

```bash
crontab -e
# Add this line:
0 2 * * * cd /path/to/konsolidat && ./deploy.sh backup >> /var/log/konsolidat-backup.log 2>&1
```

`./deploy.sh backup` runs in the Frappe image that `./deploy.sh` builds, and
it never builds that image itself: an unattended full build next to a running
ClickHouse can run the host out of memory. If the image is missing, the backup
exits 1 with `Frappe image … not found. Run ./deploy.sh first; backup does not
build.` and takes no backup. Watch the log for that line.

### Off-Server Backup

For disaster recovery, push backups off the server:

| Method | Setup | Cost |
|--------|-------|------|
| **Hetzner Storage Box** | `rsync` to storage box | ~€3/mo for 100 GB |
| **S3-compatible** (Backblaze B2, AWS S3) | Set `BACKUP_S3_BUCKET` in `.env` | ~€1/mo |
| **Hetzner Snapshots** | Click in Hetzner dashboard | ~20% of server cost |

To enable S3 backup, add to your `.env`:

```
BACKUP_S3_BUCKET=your-bucket-name
```

### Restore from Backup

```bash
./deploy.sh restore --from ./backups/2026-06-09_0200/
```

This restores MariaDB, ClickHouse, and Frappe files, then restarts services.

## Upgrading

```bash
cd konsolidat
git pull
KONSOL_BRANCH=main ./deploy.sh
```

`git pull` only updates this repository. The konsol Frappe app is a separate
checkout, staged in `docker/frappe/konsol` and baked into the image, and
`git pull` does not touch it; `./deploy.sh` stages it on every run. In order,
`./deploy.sh`:

1. starts the infrastructure (`docker compose up -d mariadb redis_cache
   redis_queue clickhouse`) and waits for it to be healthy;
2. stages the konsol app: the first run clones `KONSOL_BRANCH` (default
   `main`) from `KONSOL_REPO` (default `https://github.com/grynn-in/konsol.git`),
   later runs fetch that branch and hard-reset the staged checkout to it;
3. builds the Frappe image;
4. runs the configurator (`docker compose --profile setup run --rm configurator`),
   which runs `bench migrate` on an existing site;
5. recreates the application services with `docker compose up -d`;
6. runs the dbt build (`docker compose --profile setup run --rm dbt_init`).

### Governed exchange rates on upgrade

Consolidation translates only with the group's approved exchange rates, which konsol publishes to `epm_staging.group_exchange_rates` (see the [Exchange Rates Guide](../user-guide/exchange-rates-guide.md)). Two places in `deploy.sh` depend on them. The step numbers are the ones `deploy.sh` prints.

**Step 3/5, the configurator's `bench migrate`**, runs konsol's one-time rate adoption on a site upgrading from a version without Group Exchange Rate. It records the rate each already-translated period used as an approved Group Exchange Rate, so the first build gives the same figures. It stops the migrate, and so the deploy, when:

- a currency it would adopt has no **USD Reference (log10)**. The log says, for each one, `Create or edit ISO Currency X, set USD Reference (log10).`;
- ClickHouse cannot be read. The configurator waits up to 120 seconds for ClickHouse before it migrates.

`deploy.sh` runs under `set -e`, so a failed migrate stops it at step 3/5, before step 4/5 recreates the application services. The backend still running is the **old** release, and its Desk may not show the USD Reference (log10) field. If the field is there, set each named currency's value in **ISO Currency**. If it isn't, set the value from the checkout directory against the running backend, one command per currency (`XYZ` and `3.54` are placeholders; the value is roughly the log10 of the currency's units per 1 USD):

```bash
docker compose exec frappe_backend \
  bench --site <site> execute frappe.db.set_value --args '["ISO Currency", "XYZ", "usd_log10", 3.54]'
```

`frappe.db.set_value` writes the `usd_log10` column directly and commits, and it fails loudly if the column doesn't exist. `frappe.client.set_value` would go through the old release's view of the form and could silently skip a field it doesn't know. Then re-run `./deploy.sh`. The [Operations Runbook](operations-runbook.md#exchange-rate-problems) has the other fixes.

**Before Step 5/5**, `deploy.sh` checks the governed rates with the same dbt macros the consolidation build uses (`dbt show --inline "{{ fx_precheck() }}"` through the `dbt_init` service):

| What the check finds | What deploy.sh does |
|----------------------|---------------------|
| `epm_staging.group_exchange_rates` does not exist (the konsol migration that creates it has not run) | **Aborts** (exit 1). A fresh stack gets the table from `init-db.sql`, so this only happens on an old volume |
| No trial balance or ownership built yet | Continues; nothing to check |
| Translated keys without a usable rate (missing, duplicate, invalid, or more than 10× from the USD references) | **Warns**, lists the keys (up to 200), and continues |
| The check itself fails | Warns with dbt's error and continues |

It only warns about missing keys because the check reads the last build, and a fix made in konsol (a currency or ownership change) arrives only with this build. When keys are missing, Step 5/5 then fails: every model not downstream of `gold_consolidated_trial_balance` refreshes, the consolidated trial balance and the models that read it keep their last figures (the build refuses before it deletes anything), and the deploy exits 1 with "dbt build FAILED". Approve the listed rates in konsol (**Group Exchange Rate**) and run the build again.

!!! warning "Upgrading to the shared Frappe image (#152)"
    The first upgrade to a version with the shared `<project>-frappe:latest`
    image must be a full `./deploy.sh` run, **before the next scheduled
    backup**. Until then that image doesn't exist on the host, and
    `./deploy.sh backup` exits 1 without taking a backup (it never builds).

A plain `docker compose up -d` does **not** run the configurator, because it
is in the `setup` profile. So if you rebuild by hand, run the configurator
yourself before starting the services, or the new app code will run against
an unmigrated database.

All six Frappe-based services (`frappe_backend`, `frappe_worker`,
`frappe_scheduler`, `configurator`, `dbt_init`, `backup`) run one image,
`<project>-frappe:latest`. `<project>` is the Compose project name: the
checkout's directory name, normalised (lower-cased, any character other
than a letter, digit, `-` or `_` dropped, and leading `-` or `_` trimmed),
unless you pass `-p` or set
`COMPOSE_PROJECT_NAME`. A checkout in `./repo` gets `repo-frappe:latest`.

Scoping the tag this way means a build from a checkout with a *different*
directory name can't overwrite the image the live stack runs. Two checkouts
with the same directory name (for example, both called `repo`) still share
the tag, so give a second checkout a distinct directory name.

Don't set `COMPOSE_PROJECT_NAME` to pin the name on an existing stack. The
project name also prefixes the data volumes (`repo_mariadb_data`,
`repo_clickhouse_data`, …), so a new name starts the stack on empty volumes.

Only `frappe_backend` builds the image, so a rebuild updates all six services
together. All six have `pull_policy: never`, so Compose never looks for this
local-only image on Docker Hub. `never` rules out pulling only;
`frappe_backend` still builds.

Build the image once only. Each build runs a Node/vite asset build that takes
about 700 MB, so parallel builds of the same image can exhaust memory on an
8 GiB host, and the kernel then kills the build and the running ClickHouse.
`deploy.sh` builds with `COMPOSE_PARALLEL_LIMIT=1`. That serialises builds
with the classic builder, but it may not apply when Compose builds through
buildx/Bake. The real safeguard is that only one service has a `build:`
section.

Stacks deployed before this change also have per-service images named
`<project>-frappe_backend`, `<project>-frappe_worker` and so on. Once the
new deploy is up, nothing uses them and you can remove them with
`docker image rm`.

## Production Hardening

### Firewall

```bash
# Allow only HTTP/HTTPS and SSH
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 15432/tcp  # Excel ODBC (restrict to office IP range in production)
ufw enable
```

### Bind internal ports to localhost

In production, edit `.env` to prevent direct access to ClickHouse:

```
CLICKHOUSE_HTTP_PORT=127.0.0.1:8123
CLICKHOUSE_NATIVE_PORT=127.0.0.1:9000
```

### Environment variables

The `.credentials` file (auto-generated) contains all passwords. Keep it secure:

```bash
chmod 600 .credentials
```

## Component Sizing

### ClickHouse

| Workload | Recommended | Notes |
|----------|-------------|-------|
| Small (1-5 entities, <1M rows) | 2 vCPU, 4 GB RAM | Dev/staging |
| Medium (10-50 entities, 1-10M rows) | 4 vCPU, 16 GB RAM | Typical production |
| Large (50+ entities, 10M+ rows) | 8 vCPU, 32 GB RAM | Large enterprises |

### Frappe

| Component | Recommendation |
|-----------|---------------|
| CPU | 2+ vCPU |
| RAM | 4+ GB |
| Storage | 20 GB (app + MariaDB) |
| Workers | 2-4 Gunicorn workers |

## Next Steps

- [Operations Runbook](operations-runbook.md) — Monthly close, maintenance
- [Monitoring](monitoring.md) — Health checks and alerts
- [D365 Integration](d365-integration.md) — Airbyte + Azure AD setup
- [Security Architecture](../evaluation/security-architecture.md) — RBAC, TLS, rate limiting
