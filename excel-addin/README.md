# Konsolidat Excel add-in

Office.js shared-runtime add-in for **live `=K.EPM()` custom functions** on Excel
Desktop and Excel Online, plus a slim task pane for sign-in and diagnostics.

Verified on Excel Online (Mac) against `https://demo.konsolidat.com` (v2.0.0.0):
`=K.PING()` → `1`, `=K.EPM("AMUS", 2024, 6, "4010")` → `861245`.

## Architecture

```
Excel (Desktop / Online)
  |
  |-- Cells: =K.EPM() / =K.PING()  <-- functions.js (custom functions)
  |
  +-- Task pane: index.html        <-- login + diag (shared runtime)
           |
           v
  https://demo.konsolidat.com
    /assets/konsol/excel-addin/   (static: index.html, functions.js, functions.json)
    /api/method/konsol.api.*      (epm_batch, excel_addin_auth, ...)
```

**Shared runtime:** `manifest.demo.xml` points the manifest Script, Page, and Runtime
URLs at the same `index.html`. That page loads `office.js` then `functions.js`, so
`CustomFunctions.associate` and the pane share one browser context.

**Auth (Excel Online):** Session cookies are unreliable in the Office iframe. The pane
calls `excel_addin_auth`, stores `konsol_token` in `localStorage`, and `functions.js`
sends `X-Konsolidat-Token` on `epm_batch` requests.

**Excel Online CORS:** Excel web fetches `functions.json` cross-origin from `*.office.com`.
Caddy must return `Access-Control-Allow-Origin: *` on add-in assets (see
`docker/caddy/Caddyfile`).

## File structure

```
excel-addin/
  manifest.demo.xml     Source of truth (deployed as manifest.xml)
  manifest.xml          Copy of manifest.demo.xml for hosted/sideload URL
  package.json          Legacy npm deploy helper (prefer deploy-excel-full.sh)
  src/
    index.html          Shared runtime page: login, diag, loads functions.js
    functions.js        =K.* custom function implementations
    functions.json      Custom function metadata (Excel name registration)
    assets/             Ribbon icons (incl. icon-64.png for Admin Center)
```

Legacy `taskpane.html` / `taskpane.js` (pipeline UI) are gitignored locally — not used
for the Excel Online formula path.

## Custom functions (`=K.EPM()`)

| Function | Purpose |
|----------|---------|
| `=K.PING()` | Diagnostic — returns `1` when names registered |
| `=K.EPM(entity, year, period, account, ...)` | Value lookup via `epm_batch` |
| `=K.EPM_BUDGET(...)` | Budget amount |
| `=K.EPM_VARIANCE(...)` | Variance |
| `=K.EPM_DEBIT` / `=K.EPM_CREDIT` | Period debit/credit |
| `=K.EPMSAVE(...)` | Budget write-back on recalc |

Reads in one recalc pass are debounced into a single `epm_batch` POST. **Sign in via
the pane first** so `functions.js` has a token.

## Deploy to demo

From a machine with SSH to the demo server:

```bash
konsol_cli/scripts/deploy-excel-full.sh
```

That hot-copies add-in assets, Frappe auth modules, and the Caddyfile, then reloads
Caddy and restarts Frappe workers.

**Production (Excel Online):** deploy via **Microsoft 365 Admin Center → Integrated
apps** using the hosted manifest URL:

```
https://demo.konsolidat.com/assets/konsol/excel-addin/manifest.xml
```

Do not rely on Insert → Upload My Add-in for custom function registration on Excel web.

## Local / dev sideload

1. Serve assets from Frappe `public/excel-addin/` (or demo HTTPS).
2. Sideload `manifest.xml` (must match `manifest.demo.xml` version and ID).
3. Open pane, sign in, test `=K.PING()` then `=K.EPM(...)`.

See `konsol_cli/HANDOFF-EXCEL-ONLINE.md` for regression checklist and troubleshooting.