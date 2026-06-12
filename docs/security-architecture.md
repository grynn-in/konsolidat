# Konsol — Security Architecture & Excel Online Integration

*Last updated: 2026-06-06*

## Overview

This document describes the security architecture for exposing Konsol to Excel Online and web users, using Frappe as the application layer and ClickHouse (cloud-hosted) as the analytical backend.

**Design principles:**
- Frappe owns **application concerns** (users, config, workflows, write-back, audit)
- ClickHouse owns **analytical concerns** (GL data, consolidation, reporting)
- ClickHouse is never exposed to the internet — all access goes through Frappe or Cube
- Excel users get `=EPM.VALUE(...)` custom functions that work in Online, Desktop, and iPad

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Users                                                │
│  ┌──────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Excel    │  │ Excel Online │  │ Frappe Desk    │  │
│  │ Desktop  │  │ / iPad       │  │ (Web UI)       │  │
│  │ (ODBC)   │  │ (Add-in)     │  │                │  │
│  └────┬─────┘  └──────┬───────┘  └───────┬────────┘  │
└───────┼───────────────┼──────────────────┼────────────┘
        │               │                  │
        │          HTTPS + Entra SSO       │
        ▼               ▼                  ▼
┌──────────────────────────────────────────────────────┐
│  Frappe (Application Layer)                           │
│                                                       │
│  DocTypes:                                            │
│  ├─ Budget Entry        (write-back, workflow)        │
│  ├─ Scenario            (budget/forecast/whatif)      │
│  ├─ Consolidation Group (entities, ownership %)       │
│  ├─ IC Elimination Rule (debit/credit pairs)          │
│  ├─ Allocation Rule     (step, driver, accounts)      │
│  └─ EPM Report          (saved report definitions)    │
│                                                       │
│  Built-in: Auth, RBAC, Workflows, Audit, REST API     │
│  DB: MariaDB/PostgreSQL (metadata + config only)      │
└──────────────────┬───────────────────────────────────┘
                   │ clickhouse-connect (Python)
                   ▼
┌──────────────────────────────────────────────────────┐
│  ClickHouse (Azure / AWS — managed or self-hosted)    │
│                                                       │
│  epm_bronze  ← Airbyte (D365 OData extraction)       │
│  epm_silver  ← dbt (standardized)                    │
│  epm_gold    ← dbt (consolidated TB, IC elim, CTA)   │
│  epm_staging ← Frappe writes budget data here         │
│                                                       │
│  Cube SQL API (port 15432) → Excel ODBC / Add-in     │
└──────────────────────────────────────────────────────┘
```

---

## Security Layers

### 1. Identity & Authentication

| Mechanism | Details |
|---|---|
| **Identity provider** | Microsoft Entra ID (Azure AD) — same tenant as D365 F&O |
| **SSO** | Users authenticate via Entra; Frappe validates JWT tokens |
| **Excel Add-in auth** | MSAL.js in the add-in acquires token from Entra, passes as Bearer header |
| **Frappe native auth** | Token-based or OAuth2 for API access; session-based for Desk UI |
| **2FA** | Frappe built-in — configurable per role |

### 2. Authorization (Role-Based Access)

| Role | Desk UI | Excel Read | Excel Write | Config Edit |
|---|---|---|---|---|
| **Reader** | View reports, dashboards | `=EPM.VALUE(...)` queries | No | No |
| **Planner** | View + submit budgets | Full read | `=EPM.SUBMIT(...)` budget write-back | No |
| **Controller** | Full access | Full read | Full write | Edit consolidation groups, IC rules, allocations |
| **Admin** | Full access | Full read | Full write | All config + user management |

Frappe RBAC enforces this on every DocType and API endpoint automatically.

### 3. Transport & Network

| Layer | Implementation |
|---|---|
| **TLS** | Caddy reverse proxy with automatic Let's Encrypt certificates |
| **CORS** | Whitelist `*.officeapps.live.com` + company tenant domain |
| **Rate limiting** | 100 requests/min per user (prevents runaway Excel refresh loops) |
| **ClickHouse isolation** | Target posture: private network only, no public endpoint — all access via Frappe or Cube. The bundled `docker-compose.yml` binds ClickHouse ports to loopback (`CLICKHOUSE_BIND=127.0.0.1`) by default; see *Deployment profiles* below. |
| **Cube SQL API** | Internal network only, or VPN for desktop Excel ODBC users |

> #### Deployment profiles — read before exposing anything
>
> The two columns above describe the **intended production posture**. The
> bundled `docker-compose.yml` is a **local-dev profile** and differs in ways
> you must close before any networked deployment:
>
> | Concern | Default (bundled compose) | Production action |
> |---|---|---|
> | ClickHouse port binding | Loopback only (`CLICKHOUSE_BIND=127.0.0.1`) | Keep loopback; reach ClickHouse via the Caddy proxy or a private network. Never bind `0.0.0.0` on a public host. |
> | ClickHouse transport | Plaintext HTTP (`CLICKHOUSE_SECURE=false`) | Set `CLICKHOUSE_SECURE=true` / `CLICKHOUSE_VERIFY=true` and use the dbt `prod` target (`DBT_TARGET=prod`). |
> | Secrets | `deploy.sh` generates random passwords into `.env`; compose refuses to start if any password is unset | Use a real secrets manager; rotate the generated values. |
> | Cube API secret | Required (compose fails if unset) | Keep; rotate per environment. |
>
> "Encryption in transit — TLS everywhere" (below) is only true once
> `CLICKHOUSE_SECURE=true`; the loopback-only default keeps the plaintext hop
> on the host, off the wire.

### 4. Audit Trail

Frappe provides automatic audit logging on every DocType:
- Every create, update, delete is logged with user, timestamp, and field-level diff
- Budget submissions tracked: who submitted, when, what values, approval chain
- API access logged: which user queried which dimensions
- Configuration changes tracked: who changed consolidation groups, IC rules, ownership %

No custom code needed — this is Frappe's built-in behavior.

### 5. Data Protection

| Concern | Approach |
|---|---|
| **PII in GL data** | ClickHouse stores account-level aggregates, not transactional PII. Personal data stays in D365. |
| **Budget confidentiality** | Role-based: planners see only their entity/cost center (Frappe user permissions) |
| **Encryption at rest** | ClickHouse Cloud and Azure/AWS managed disks provide this by default |
| **Encryption in transit** | TLS everywhere once `CLICKHOUSE_SECURE=true` (Frappe ↔ browser via Caddy, Frappe/dbt ↔ ClickHouse, Airbyte ↔ D365). The local-dev default leaves the Frappe ↔ ClickHouse hop plaintext on loopback. |
| **Backup** | ClickHouse Cloud: automatic. Self-hosted: scheduled snapshots to blob storage. |

### 6. Source Connector Security (Airbyte → D365 F&O)

The custom `source-d365-fno` connector authenticates to Dynamics 365 via Azure
AD v2.0 **client-credentials** OAuth:

- **Credential handling** — `tenant_id`, `client_id`, and `client_secret` are
  all marked `airbyte_secret: true` in `spec.yaml`, so Airbyte stores them
  encrypted and masks them in logs. Tokens are cached in memory with a 60-second
  expiry buffer and never persisted.
- **No secret leakage on failure** — `check_connection` returns a generic
  message (HTTP status only); the raw Azure AD response body is logged at debug
  level, never surfaced to the UI.
- **Transport** — token acquisition and all OData calls use HTTPS with default
  certificate verification.
- **Throttling** — the connector retries `429`/`5xx` with `Retry-After`-aware
  backoff so it degrades politely against D365's OData limits.
- **Data scope** — reads are cross-company by default (required for
  consolidation); set `cross_company: false` to scope a sync to the service
  principal's default company.
- **Recommendation** — grant the Azure AD app the **minimum** D365 data-entity
  permissions needed, and rotate the client secret per Azure AD policy.

---

## Excel Online Integration: EPM.VALUE() Custom Function

### The HSGETVALUE Equivalent

Konsol provides an Excel Custom Functions Add-in that registers cell formulas working in Excel Online, Desktop, and iPad:

| Formula | Purpose | API Endpoint |
|---|---|---|
| `=EPM.VALUE(entity, year, period, account, scenario, [cost_center], [dept])` | Single cell value (HSGETVALUE equivalent) | `GET /api/method/konsol.api.get_value` |
| `=EPM.CONSOLIDATED(entity, year, period, account, measure)` | Consolidated group amount (after IC elim + CTA) | `GET /api/method/konsol.api.get_consolidated` |
| `=EPM.VARIANCE(entity, year, period, account)` | Actual vs budget variance | `GET /api/method/konsol.api.get_variance` |
| `=EPM.MEMBERS(dimension)` | Populate dropdown lists (entities, accounts, periods) | `GET /api/method/konsol.api.get_members` |
| `=EPM.SUBMIT(range, scenario_id)` | Write budget data back (planner role only) | `POST /api/method/konsol.api.submit_budget` |

### Example Usage in a Spreadsheet

```
       A              B          C           D            E
1   Entity         Account    Actuals     Budget       Variance
2   USMF           4000       =EPM.VALUE( =EPM.VALUE(  =EPM.VARIANCE(
                               "USMF",     "USMF",      "USMF",
                               2026,1,     2026,1,      2026,1,
                               "4000",     "4000",      "4000")
                               "actuals")  "budget")
3   GBMF           4000       125,340     130,000      (4,660)
4   DKMF           5100        45,200      42,000       3,200
```

### How It Compares to Hyperion SmartView

| | **Hyperion SmartView** | **Konsol Add-in** |
|---|---|---|
| Cell formula | `=HsGetValue(...)` | `=EPM.VALUE(...)` |
| Bulk refresh | Ad hoc retrieve | Auto-recalc or ribbon refresh button |
| Submit data | SmartView submit | `=EPM.SUBMIT(range, scenario)` |
| Auth | EPM workspace login | Entra ID SSO (automatic) |
| Install | SmartView plugin (desktop only) | Office Add-in (web + desktop + iPad) |
| Works in Excel Online | **No** | **Yes** |
| Works on iPad | **No** | **Yes** |

### Add-in Technical Details

- **Technology:** TypeScript, Office.js Custom Functions API
- **Auth:** MSAL.js acquires Entra ID token; passed as Bearer header on every API call
- **Caching:** Results cached for 5 minutes per dimension combination (configurable)
- **Batch optimization:** Multiple `=EPM.VALUE(...)` calls in a sheet are batched into a single `/api/method/konsol.api.batch` request during recalc
- **Deployment:** Upload to Microsoft 365 admin center for org-wide availability
- **Scaffold:** `npx yo office --type excel-functions-shared` generates the project skeleton

---

## Frappe DocTypes (Replace CSV Seeds)

Configuration that was previously managed as CSV seed files in dbt is now managed as Frappe DocTypes — web-editable, versioned, audited, and role-protected.

| DocType | Replaces | Key Fields | Workflow |
|---|---|---|---|
| **Budget Entry** | `epm_staging.budget_input` | entity, year, period, account, cost_center, amount, scenario, submitted_by | Draft → Submitted → Approved |
| **Scenario** | `scenario_definitions.csv` | scenario_id, name, type (budget/forecast/whatif), base_scenario, status | No |
| **Consolidation Group** | `consolidation_groups.csv` | group_name, entity, ownership_pct, reporting_currency | No |
| **IC Elimination Rule** | `ic_elimination_rules.csv` | debit_account, credit_account, description | No |
| **Allocation Rule** | `allocation_rules.csv` | step_order, source_account, target_account, driver_type, source_cost_center | No |
| **Allocation Driver** | `allocation_drivers_*.csv` | cost_center, fiscal_period, driver_value, driver_type | No |

### Config Sync Flow

```
Controller edits Consolidation Group in Frappe Desk
  → Frappe saves to MariaDB (audited)
  → Frappe server script writes to ClickHouse epm_staging.consolidation_groups
  → Dagster detects change → triggers dbt build
  → Gold layer regenerated with new ownership %
  → Excel users see updated consolidated numbers on next refresh
```

---

## Budget Approval Workflow (Frappe Built-in)

```
Planner submits budget in Excel
  → =EPM.SUBMIT(B2:H50, "BUDGET_2026_Q2")
  → Frappe creates Budget Entry DocType records (status: Draft)
  → Planner clicks "Submit" in Frappe Desk (or auto-submits via API)
  → Workflow transitions to "Pending Approval"
  → Controller receives email notification
  → Controller reviews in Frappe Desk → Approves or Rejects
  → On Approve: data written to ClickHouse epm_staging.budget_input
  → dbt unions into gold_scenario_trial_balance
  → Variance analysis updates automatically
```

No custom workflow engine needed — this is Frappe's standard DocType workflow feature.

---

## ClickHouse Hosting Options

| Option | Service | Cost (~50GB GL data) | Managed? |
|---|---|---|---|
| **ClickHouse Cloud** | clickhouse.com (on Azure/AWS) | ~$200–400/mo | Yes — auto-scaling, backups, monitoring |
| **Azure VM** | D4s_v5 + managed disk | ~$150–250/mo | Self-hosted — you manage ClickHouse |
| **AWS EC2** | m6i.xlarge + EBS | ~$150–250/mo | Self-hosted — you manage ClickHouse |
| **Aiven for ClickHouse** | Managed on Azure/AWS | ~$300–500/mo | Yes — managed, multi-cloud |

For mid-market EPM workloads (a few GB of GL data, monthly refresh cycles), the smallest ClickHouse Cloud tier is sufficient.

---

## What Frappe Closes vs. FastAPI

| Gap | FastAPI (current) | Frappe |
|---|---|---|
| User management & SSO | Build from scratch | **Built-in** — users, roles, 2FA, OAuth, LDAP |
| Role-based access | Build from scratch | **Built-in** — RBAC on every DocType |
| Workflow/approvals | Not implemented | **Built-in** — multi-step with email notifications |
| Audit trail | Build from scratch | **Built-in** — every change logged with field-level diff |
| Web UI for end users | Streamlit (admin only) | **Built-in** — Desk UI, list views, forms, reports |
| REST API | Manual endpoint coding | **Built-in** — auto-generated for every DocType |
| Report builder | None | **Built-in** — query builder + chart views |
| Real-time updates | None | **Built-in** — Socket.io |
| Config management | CSV seeds in git | **Built-in** — DocTypes (web-editable, versioned) |

### Remaining Gaps (dbt analytical layer — not Frappe's job)

| Gap | Effort | Owner |
|---|---|---|
| Cash flow statement | ~2–3 days dbt work | Data engineer |
| Multi-GAAP / dual reporting | ~1 week dbt work | Data engineer |
| Rolling forecasts | ~2–3 days dbt work | Data engineer |

---

## Build Effort Summary

| Component | Effort | Notes |
|---|---|---|
| Frappe app scaffold + DocTypes | 2–3 days | `bench new-app konsol`, define 6 DocTypes |
| ClickHouse integration (server scripts) | 1–2 days | `clickhouse-connect` from Frappe to read/write |
| Entra ID SSO configuration | 1 day | Frappe Social Login + Entra app registration |
| Budget approval workflow | Half day | Frappe workflow builder (configuration, not code) |
| Caddy reverse proxy + TLS | Half day | ~20 lines of Caddyfile |
| CORS configuration | 2 hours | Frappe `site_config.json` |
| Excel Custom Functions Add-in | 2–3 days | TypeScript, MSAL.js, Office.js scaffold |
| Add-in deployment (org-wide) | Half day | Upload to Microsoft 365 admin center |
| Migrate CSV seeds → DocTypes | 1 day | One-time data migration |
| **Total** | **~10–12 days** | |
