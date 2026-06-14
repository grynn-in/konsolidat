# Excel Office.js Task Pane Add-in

Pipeline orchestration sidebar for Excel. Lets users log in to Frappe, trigger
"Extract + dbt Build" runs, and monitor pipeline status -- all from a task pane
inside the Excel ribbon.

This add-in **complements** the VBA macros in `excel/OpenEPM.bas`, which handle
`=EPM()` data formulas and batch retrieval. The task pane handles orchestration;
the VBA handles data.

## Architecture

```
+---------------------+          HTTPS (same origin)
|  Excel (Desktop)    |  +---------------------------------+
|                     |  |                                 |
|  +--------------+   |  |   Frappe / konsol               |
|  | VBA macros   |---|---->  /api/method/konsol.api.*     |
|  | =EPM() cells |   |  |   (data formulas, batch query) |
|  +--------------+   |  |                                 |
|                     |  |                                 |
|  +--------------+   |  |                                 |
|  | Task Pane    |---|---->  /api/method/login             |
|  | (Office.js   |   |  |   /api/method/logout            |
|  |  webview)    |---|---->  /api/resource/Pipeline Run    |
|  |              |   |  |   /api/method/konsol.pipeline.*  |
|  +--------------+   |  |     .trigger_pipeline            |
|                     |  |                                 |
+---------------------+  +---------------------------------+
                              https://epm.local
                              Bare-metal Frappe bench
                              /home/pd/frappe-bench
```

The task pane HTML/JS/CSS is served by Frappe as static assets at
`/assets/konsol/excel-addin/`. Because the webview loads from the same origin
as the API, all `fetch()` calls use relative paths with `credentials: "include"`
-- no CORS configuration is needed.

## File Structure

```
excel-addin/
  manifest.xml          Office Add-in XML manifest (sideload this)
  package.json          Deploy script only -- no build step
  .gitignore            Excludes node_modules/, cert.pem, key.pem
  src/
    taskpane.html       Main HTML (login form + status card)
    taskpane.js         All logic: auth, pipeline status, polling, trigger
    taskpane.css        Fluent-UI-inspired styles
    assets/
      icon-16.png       Ribbon icon 16x16
      icon-32.png       Ribbon icon 32x32
      icon-80.png       Ribbon icon 80x80
```

## API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/method/login` | POST | Authenticate with Frappe (cookie-based session) |
| `/api/method/frappe.auth.get_logged_user` | GET | Check if session is still active |
| `/api/method/logout` | POST | Destroy session |
| `/api/resource/Pipeline Run` | GET | Fetch latest pipeline run (status, rows_synced, dbt_result) |
| `/api/method/konsol.pipeline.doctype.pipeline_run.pipeline_run.trigger_pipeline` | POST | Trigger a new Extract + dbt Build run |
| `/api/method/konsol.api.epm_batch` | POST | Batch value retrieval for the `=K.EPM()` Custom Functions |
| `/api/method/konsol.api.budget_cell_save` | POST | Write-back for `=K.EPMSAVE()` |

## Custom Functions (`=K.EPM()`)

In addition to the task pane, this add-in registers **Office.js Custom Functions** —
live, auto-recalculating worksheet formulas under the **`K`** namespace. They
**complement** the VBA in `excel/OpenEPM.bas` (which stays in place); both can be used
in the same workbook because `=EPM()` (VBA, bare) and `=K.EPM()` (add-in, namespaced)
never collide. Unlike the VBA, the Custom Functions fetch on their own — no manual
Refresh — and work on Windows, Mac, and Excel on the web.

| Function | Purpose |
|----------|---------|
| `=K.EPM(entity, year, period, account, [measure], [scenario], [costCenter], [department], [scenarioId])` | Value lookup (default `period_net_amount` / `actuals`). `period` accepts 1-12, Q1-Q4, H1-H2, FY. |
| `=K.EPM_BUDGET(entity, year, period, account, [costCenter], [department], [scenarioId])` | Budget amount |
| `=K.EPM_VARIANCE(...)` | Variance (absolute) |
| `=K.EPM_DEBIT(entity, year, period, account, [costCenter], [department])` | Period debit |
| `=K.EPM_CREDIT(...)` | Period credit |
| `=K.EPMSAVE(amount, entity, year, period, account, scenarioId, layer, [costCenter], [department])` | Write a budget cell back on recalc (`layer` ∈ base/challenge/management/board) |

All `=K.EPM*` reads in a recalc pass are debounced into a **single** `epm_batch` POST
(chunked at 2000). Auth uses the same session cookie as the task pane — **sign in via the
pane first**.

The manifest declares a **shared runtime** (`<Runtimes>` + the `SharedRuntime`
requirement): the task pane and the custom functions run in one browser runtime, so the
session cookie set at login is sent by the functions' `fetch()` calls. (The default
JS-only custom-functions runtime does not support cookies, so cookie-based auth would
401.) The shared page is `taskpane.html` / `index.html`, which loads `functions.js` to
register the functions. Files: `src/functions.json` (metadata) and `src/functions.js`
(logic); wired in `manifest.xml` via the `CustomFunctions` extension point under
`<AllFormFactors>`.

## Deploy

No build step. Copy source files to the konsol Frappe app's `public/` directory
(symlinked to `sites/assets/konsol/`):

```bash
# From the repo root
cp excel-addin/src/taskpane.html /home/pd/frappe-bench/apps/konsol/konsol/public/excel-addin/index.html
cp excel-addin/src/taskpane.js   /home/pd/frappe-bench/apps/konsol/konsol/public/excel-addin/
cp excel-addin/src/taskpane.css  /home/pd/frappe-bench/apps/konsol/konsol/public/excel-addin/
cp excel-addin/src/assets/*.png  /home/pd/frappe-bench/apps/konsol/konsol/public/excel-addin/assets/
```

Or use the npm script (adjusts paths from the excel-addin/ directory):

```bash
cd excel-addin
npm run deploy
```

After copying, clear the Frappe cache so the new files are served:

```bash
cd /home/pd/frappe-bench
bench --site epm.local clear-cache
```

## Sideload in Excel

### Prerequisites

- For local dev, the manifest uses `http://localhost:8069` (Office.js allows
  HTTP on localhost). No HTTPS or certs needed.
- For production, set up HTTPS via `bench setup production` (nginx) and update
  the manifest URLs to `https://your-domain/assets/konsol/excel-addin/...`.
- **Admin-managed orgs**: sideloading may be blocked. Ask IT to either enable
  "Upload My Add-in" or deploy the manifest via Microsoft 365 Admin Center.

### Windows (Excel Desktop)

1. Open Excel and create or open a workbook.
2. Go to **File > Options > Trust Center > Trust Center Settings > Trusted Add-in Catalogs**.
3. Alternatively, use the faster method:
   - Go to **Insert > My Add-ins > Upload My Add-in**.
   - Browse to `excel-addin/manifest.xml` and click **OK**.
4. The "OpenEPM" button appears on the **Home** tab in the ribbon.
5. Click it to open the task pane.

### Shared Network Catalog (multi-user)

1. Place `manifest.xml` on a shared network folder (e.g., `\\server\addins\`).
2. In Excel: **File > Options > Trust Center > Trust Center Settings > Trusted Add-in Catalogs**.
3. Add the network path as a trusted catalog.
4. Restart Excel. The add-in appears under **Insert > My Add-ins > Shared Folder**.

### Microsoft 365 Admin Center (org-wide)

1. Upload `manifest.xml` via the Microsoft 365 admin center under
   **Settings > Integrated Apps > Upload custom apps**.
2. The add-in becomes available to all users in the tenant.

## How It Works

1. **Login** -- User enters Frappe credentials. The task pane calls
   `/api/method/login` which sets a session cookie.
2. **Status display** -- On login (and on each poll), the pane fetches the most
   recent `Pipeline Run` document from Frappe and renders status, start time,
   rows synced, and dbt result.
3. **Trigger** -- The "Run Extract + dbt Build" button calls the whitelisted
   Frappe method `trigger_pipeline`, which creates a new Pipeline Run document
   and kicks off the extract/transform background job.
4. **Auto-refresh** -- While a run is in an active state (Queued, Extracting,
   Transforming), the pane polls every 5 seconds. Polling stops when the run
   reaches Success or Failed.
