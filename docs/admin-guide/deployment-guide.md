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
│  Step 1: Check prerequisites (Docker, Docker Compose)            │
│          Generate random passwords → .env                        │
│                                                                  │
│  Step 2: Start infrastructure                                    │
│          ┌──────────┐ ┌────────┐ ┌────────┐ ┌────────────┐      │
│          │ MariaDB  │ │ Redis  │ │ Redis  │ │ ClickHouse │      │
│          │ (Frappe  │ │ (cache)│ │(queue) │ │  (OLAP)    │      │
│          │  data)   │ │        │ │        │ │            │      │
│          └──────────┘ └────────┘ └────────┘ └────────────┘      │
│          Wait for all healthchecks ✓ ✓ ✓ ✓                      │
│                                                                  │
│  Step 3: Build Frappe + Konsol image                             │
│          (first run only — cached after that)                    │
│                                                                  │
│  Step 4: Create Frappe site + install Konsol app                 │
│          • Creates database                                      │
│          • Sets admin password                                   │
│          • Configures ClickHouse connection                      │
│                                                                  │
│  Step 5: Start application services                              │
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
│  Step 6: Seed demo data + run dbt build                          │
│          • Creates gold models (trial balance, P&L, etc.)        │
│          • Excel reports work immediately                        │
│                                                                  │
│  Step 7: Print URLs + credentials                                │
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

## Connecting Real ERP Data

The system works with demo data out of the box. To connect a real D365 Finance & Operations instance:

1. Log into Frappe: `http://your-server:8069`
2. Go to **EPM Settings**
3. Enter your D365 credentials (Tenant ID, Client ID, Client Secret, Environment URL)
4. Click **Run Pipeline** to sync data

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
docker compose build frappe_backend
docker compose up -d
```

The configurator automatically runs `bench migrate` on existing sites.

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
