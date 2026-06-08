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
