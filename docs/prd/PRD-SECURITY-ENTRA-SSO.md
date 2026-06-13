# PRD: Security & Microsoft Entra ID SSO

**Status:** Not Started
**Date:** 2026-06-13
**Phase:** Phase 4 — Security & SSO
**Repos:** `konsol` (Frappe app — Social Login, roles, `konsol.api`, `clickhouse.py`), `konsolidat` (data stack — `docker-compose.yml`, `docker/caddy/Caddyfile`)

## Problem

The security *architecture* is documented (`docs/security-architecture.md`) and the recent hardening (konsol#12, konsolidat#34) landed table-name validation, entity authz, HMAC webhooks, `clickhouse_secure`/`verify_tls`, loopback ClickHouse binds and required-secret enforcement. But the **identity, edge, and network-isolation layers are not yet built**:

- No SSO. Users log in with local Frappe passwords; there is no Entra ID provider, no `group → role` mapping. Roadmap Phase 4.1 is "Not started".
- The Caddyfile (`docker/caddy/Caddyfile`) is a bare reverse proxy — no `tls`, no CORS allowlist for Excel Online, no rate limiting. Runaway `=EPM.VALUE()` recalc loops can hammer `konsol.api` unbounded.
- ClickHouse ports (`8123`, `9000`, `15432`) are bound via `${CLICKHOUSE_BIND:-127.0.0.1}` — safe by default on a single host, but there is no enforced production posture preventing an operator from setting `CLICKHOUSE_BIND=0.0.0.0`, and no verification step. Roadmap 4.3 requires "no ClickHouse ports reachable from public internet".
- Role naming is inconsistent: code has `EPM User/Analyst/Admin` (build governance) and `Budget Submitter/Controller/Manager/Approver`, while the security model and Excel add-in assume **Reader/Planner/Controller/Admin**. SSO needs one canonical mapping.

## Solution

Configure Frappe Social Login against Microsoft Entra ID (OAuth2/OIDC), map Entra group claims to four canonical Frappe roles on login, and harden the Caddy edge (auto-TLS, CORS for Excel Online, 100 req/min/user rate limiting) while pinning ClickHouse to the internal Docker network only in the production compose profile.

## Scope

### 1. Entra ID OAuth2 / OIDC (konsol)

Use Frappe's built-in **Social Login Key** (OIDC provider), same tenant as the D365 F&O connector.

| Setting | Value |
|---|---|
| Provider | Custom OIDC (`social_login_key` = `entra`) |
| Authorize URL | `https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token` |
| Userinfo / JWKS | `https://graph.microsoft.com/oidc/userinfo`, `.../discovery/v2.0/keys` |
| Scopes | `openid profile email` + `GroupMember.Read.All` (or `groups` optional claim) |
| Redirect URI | `https://{SITE_DOMAIN}/api/method/frappe.integrations.oauth2_logins.custom/entra` |

Secrets (`tenant_id`, `client_id`, `client_secret`) stored encrypted in the Social Login Key doctype / `site_config.json`, never in compose.

#### 1.1 Group → Role mapping

Canonical roles (supersede ad-hoc names; `EPM Admin` retained for build-governance approvals, granted alongside `Konsol Admin`):

| Entra ID group (configurable) | Frappe role | Capabilities (per `docs/security-architecture.md` §2) |
|---|---|---|
| `Konsol-Readers` | **Konsol Reader** | `=EPM.VALUE` read; view reports; no write, no config |
| `Konsol-Planners` | **Konsol Planner** | Reader + `=EPM.SUBMIT` budget write-back |
| `Konsol-Controllers` | **Konsol Controller** | full read/write + edit Consolidation Group / IC Elimination Rule / Allocation Rule |
| `Konsol-Admins` | **Konsol Admin** + `EPM Admin` | all config, user management, approve high-risk Pipeline Build Requests |

- New module `konsol/auth.py` exposes `map_entra_groups(login_manager)`, wired to the `on_login` / `on_social_login` hook in `hooks.py`. Pure mapping fn `resolve_roles(group_ids: list[str], mapping: dict) -> set[str]` (testable without a site, per the no-monkeypatch convention).
- Mapping table stored on **EPM Settings** (new child table `entra_group_role_map`: `entra_group_id`, `frappe_role`) so it is web-editable and audited.
- On each login: roles in the mapping are **synced** (added if in claim, removed if absent) so Entra is the source of truth; roles outside the mapping (e.g. `System Manager`) are left untouched.
- Deny-by-default: a user with zero mapped groups gets no Konsol role and lands on a "no access" page (consistent with the entity-authz deny-by-default decision).

### 2. Caddy edge: TLS, CORS, rate limiting (konsolidat)

Extend `docker/caddy/Caddyfile` (currently bare). Caddy auto-provisions Let's Encrypt certs for `{$SITE_DOMAIN}`.

| Concern | Directive |
|---|---|
| TLS | Automatic HTTPS on `{$SITE_DOMAIN}` (drop the `:443` playground block in prod, or gate behind a profile) |
| CORS allowlist | `Access-Control-Allow-Origin` matched against `https://*.officeapps.live.com`, `https://*.officeapps-df.live.com`, and `{$TENANT_DOMAIN}`; `Allow-Credentials: true`; handle `OPTIONS` preflight with 204 |
| Rate limiting | `rate_limit` (caddy-ratelimit module) keyed by authenticated user — **100 req/min/user**; key = `{http.request.header.X-Frappe-User}` falling back to client IP; respond `429` over budget |
| Cube proxy | keep `handle /api/method/konsol.cube_proxy/*` → `cubejs:4000`; rate limit applies before proxy |

Rate-limit threshold and CORS origins parameterised via env (`RATE_LIMIT_PER_MIN:-100`, `EXCEL_CORS_ORIGINS`) so dev can relax them.

### 3. ClickHouse network isolation (konsolidat)

Production posture: ClickHouse reachable **only** on the internal Docker network, consumed by `frappe_backend`, `frappe_worker`, `dbt`, and `cubejs` by service name.

| Item | Action |
|---|---|
| Host port bindings | Production compose profile (`docker-compose.prod.yml` overlay) **removes** the three `ports:` entries (`8123`, `9000`, `15432`) on the `clickhouse` service — internal network only, no host publish |
| Default dev | `${CLICKHOUSE_BIND:-127.0.0.1}` retained for local-dev (loopback only, never `0.0.0.0`) |
| Excel ODBC (15432) | reached via Caddy/Cube SQL API or VPN, not a public host port |
| Transport | `clickhouse_secure=true` / `verify_tls=true` on EPM Settings drive `konsol/clickhouse.py:get_connection()` to use HTTPS to ClickHouse in prod (extend `get_connection()` to read these fields; dbt uses `DBT_TARGET=prod`) |
| Verification | `scripts/verify_isolation.sh` asserts no `clickhouse` host port is listening on a non-loopback interface and that the public Caddy endpoint exposes no ClickHouse path |

## Out of Scope

- MSAL.js token acquisition inside the Excel add-in (Office.js add-in already uses Frappe session-cookie auth per Phase 5; Entra-token Bearer flow for the add-in is a later enhancement).
- Frappe 2FA enrolment and conditional-access policy authoring in Entra (configured tenant-side, not in this repo).
- Per-entity / per-cost-center row-level budget confidentiality (entity authz already shipped in konsol#12; not re-litigated here).
- ClickHouse sharding/cluster TLS between nodes (Phase 7 production hardening).
- WAF / DDoS beyond Caddy rate limiting.

## Acceptance Criteria

1. A Social Login Key named `entra` exists; clicking "Login with Microsoft" redirects to `login.microsoftonline.com` and returns an authenticated Frappe session.
2. `resolve_roles(["<Konsol-Planners gid>"], mapping)` returns exactly `{"Konsol Planner", "Konsol Reader"}` (or the configured set); a user in `Konsol-Admins` resolves to `{"Konsol Admin", "EPM Admin"}`.
3. After login, the user's Frappe roles equal the mapped set for their current Entra groups — a role removed in Entra is removed on next login.
4. A user in no mapped group receives no Konsol role and is denied Desk/API access (deny-by-default).
5. `curl -I https://{SITE_DOMAIN}` returns a valid Let's Encrypt cert chain (HTTP→HTTPS redirect on `:80`).
6. A cross-origin `OPTIONS` preflight from `https://x.officeapps.live.com` returns `204` with the origin echoed; an origin not on the allowlist gets no `Access-Control-Allow-Origin`.
7. The 101st request within 60s from one authenticated user to `konsol.api` returns HTTP `429`.
8. In the prod compose profile, `docker compose config` shows the `clickhouse` service with **no** `ports:` published; `verify_isolation.sh` exits 0.
9. With `clickhouse_secure=true`, `get_connection()` / `connection_url()` produces an `https://` ClickHouse URL and `check_health()` succeeds against the TLS endpoint.
10. `pytest konsol/tests/test_auth.py` (pure `resolve_roles` + `hooks.py` source-inspection) passes with no site required.

## Open Questions

- Group claim delivery: emit group **object IDs** as an optional claim, or call Microsoft Graph `GroupMember.Read.All` at login? (Object IDs avoid an extra Graph call but the map must store GUIDs, not names.)
- Should `System Manager` be auto-granted to `Konsol-Admins`, or kept manual to preserve a break-glass local admin?
- Rate-limit identity when the request is pre-auth (login page, static add-in assets) — fall back to IP only, or exempt those paths?
- Reconcile legacy `Budget Submitter/Controller/Manager/Approver` workflow roles with the four canonical roles — alias, migrate, or keep both?
