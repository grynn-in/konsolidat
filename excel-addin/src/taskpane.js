/* global Office */

// Same-origin: taskpane is served by Frappe, so no base URL needed
const FRAPPE_URL = "";
let pollTimer = null;

// ── Office init ──────────────────────────────────────────────────────
Office.onReady(function () {
  checkSession();
});

// ── DOM helpers ──────────────────────────────────────────────────────
function show(id) { document.getElementById(id).hidden = false; }
function hide(id) { document.getElementById(id).hidden = true; }
function setText(id, text) { document.getElementById(id).textContent = text; }

function showLoading() { show("loading"); }
function hideLoading() { hide("loading"); }

function showError(id, msg) {
  var el = document.getElementById(id);
  el.textContent = msg;
  el.hidden = false;
}
function hideError(id) { document.getElementById(id).hidden = true; }

// ── Auth ─────────────────────────────────────────────────────────────
function login() {
  var email = document.getElementById("email").value.trim();
  var password = document.getElementById("password").value;

  if (!email || !password) {
    showError("login-error", "Email and password are required.");
    return;
  }

  hideError("login-error");
  showLoading();

  fetch(FRAPPE_URL + "/api/method/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ usr: email, pwd: password })
  })
    .then(function (res) {
      if (!res.ok) throw new Error("Invalid credentials");
      return res.json();
    })
    .then(function () {
      hideLoading();
      showStatusView(email);
    })
    .catch(function (err) {
      hideLoading();
      showError("login-error", err.message);
    });
}

function checkSession() {
  fetch(FRAPPE_URL + "/api/method/frappe.auth.get_logged_user", {
    credentials: "include"
  })
    .then(function (res) {
      if (!res.ok) throw new Error("Not logged in");
      return res.json();
    })
    .then(function (data) {
      showStatusView(data.message);
    })
    .catch(function () {
      showLoginView();
    });
}

function logout() {
  stopPolling();
  fetch(FRAPPE_URL + "/api/method/logout", {
    method: "POST",
    credentials: "include"
  }).finally(function () {
    showLoginView();
  });
}

function showLoginView() {
  show("login-section");
  hide("main-section");
}

function showStatusView(user) {
  hide("login-section");
  show("main-section");
  setText("user-label", user);
  updateSheetInfo();
  loadPipelineStatus();
}

// ── Tab switching ────────────────────────────────────────────────
function switchTab(tabName) {
  var tabs = document.querySelectorAll(".tab");
  var contents = document.querySelectorAll(".tab-content");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].classList.remove("active");
    contents[i].classList.remove("active");
  }
  document.querySelector('.tab[data-tab="' + tabName + '"]').classList.add("active");
  document.getElementById("tab-" + tabName).classList.add("active");

  if (tabName === "budget") {
    updateSheetInfo();
  }
}

// ── Pipeline status ──────────────────────────────────────────────────
function loadPipelineStatus() {
  var fields = JSON.stringify([
    "name", "status", "creation", "rows_synced", "dbt_result"
  ]);
  var url = FRAPPE_URL + "/api/resource/Pipeline Run"
    + "?fields=" + encodeURIComponent(fields)
    + "&limit_page_length=1"
    + "&order_by=creation desc";

  fetch(url, { credentials: "include" })
    .then(function (res) {
      if (!res.ok) throw new Error("Failed to load pipeline status");
      return res.json();
    })
    .then(function (data) {
      var runs = data.data || [];
      if (runs.length === 0) {
        show("no-runs");
        hide("run-details");
        stopPolling();
        return;
      }

      hide("no-runs");
      show("run-details");

      var run = runs[0];
      renderRun(run);

      var active = ["Queued", "Extracting", "Transforming"];
      if (active.indexOf(run.status) !== -1) {
        startPolling();
      } else {
        stopPolling();
      }
    })
    .catch(function () {
      show("no-runs");
      hide("run-details");
    });
}

function renderRun(run) {
  var statusEl = document.getElementById("run-status");
  statusEl.textContent = run.status || "Unknown";
  statusEl.className = "badge " + badgeClass(run.status);

  setText("run-started", formatDate(run.creation));
  setText("run-rows", run.rows_synced != null ? run.rows_synced.toLocaleString() : "—");
  setText("run-dbt", run.dbt_result || "—");
}

function badgeClass(status) {
  var map = {
    Queued: "badge-queued",
    Extracting: "badge-extracting",
    Transforming: "badge-transforming",
    Success: "badge-success",
    Failed: "badge-failed"
  };
  return map[status] || "badge-default";
}

function formatDate(iso) {
  if (!iso) return "—";
  var d = new Date(iso);
  return d.toLocaleString(undefined, {
    month: "short", day: "numeric",
    hour: "2-digit", minute: "2-digit"
  });
}

// ── Trigger pipeline ─────────────────────────────────────────────────
function triggerPipeline() {
  var btn = document.getElementById("run-btn");
  btn.disabled = true;
  hideError("run-error");

  fetch(FRAPPE_URL + "/api/method/konsol.pipeline.doctype.pipeline_run.pipeline_run.trigger_pipeline", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include"
  })
    .then(function (res) {
      if (!res.ok) throw new Error("Failed to trigger pipeline");
      return res.json();
    })
    .then(function () {
      btn.disabled = false;
      loadPipelineStatus();
    })
    .catch(function (err) {
      btn.disabled = false;
      showError("run-error", err.message);
    });
}

// ── Polling ──────────────────────────────────────────────────────────
function startPolling() {
  if (pollTimer) return;
  show("polling-indicator");
  document.getElementById("run-btn").disabled = true;
  pollTimer = setInterval(loadPipelineStatus, 5000);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
  hide("polling-indicator");
  document.getElementById("run-btn").disabled = false;
}

// ── Budget: Sheet Info ──────────────────────────────────────────
function updateSheetInfo() {
  Excel.run(function (context) {
    var sheet = context.workbook.worksheets.getActiveWorksheet();
    var infoRange = sheet.getRange("A1:B7");
    infoRange.load("values");

    var usedRange = sheet.getUsedRange();
    usedRange.load("rowCount");

    return context.sync().then(function () {
      var info = infoRange.values;
      var scenarioId = "";
      var scenarioType = "";
      var fiscalYear = "";
      var layer = "";

      for (var r = 0; r < info.length; r++) {
        var label = String(info[r][0]).trim().toUpperCase();
        var val = info[r][1];
        if (label === "SCENARIO ID:") scenarioId = val;
        else if (label === "TYPE:") scenarioType = val;
        else if (label === "FISCAL YEAR:") fiscalYear = val;
        else if (label === "LAYER:") layer = val;
      }

      // Count data rows: find header row, then count rows after it
      var headerRange = sheet.getRange("A1:A20");
      headerRange.load("values");
      return context.sync().then(function () {
        var headerRow = -1;
        var vals = headerRange.values;
        for (var i = 0; i < vals.length; i++) {
          if (String(vals[i][0]).trim().toUpperCase() === "SCENARIO ID") {
            headerRow = i;
            break;
          }
        }

        var dataRows = 0;
        var entities = new Set();
        if (headerRow >= 0) {
          dataRows = usedRange.rowCount - headerRow - 1;
          if (dataRows < 0) dataRows = 0;
        }

        setText("info-scenario", scenarioId || "—");
        setText("info-type", scenarioType || "—");
        setText("info-year", fiscalYear || "—");
        setText("info-layer", layer || "—");
        setText("info-rows", dataRows > 0 ? dataRows : "—");

        // Count unique entities
        if (headerRow >= 0 && dataRows > 0) {
          var entityRange = sheet.getRange("B" + (headerRow + 2) + ":B" + usedRange.rowCount);
          entityRange.load("values");
          return context.sync().then(function () {
            var eVals = entityRange.values;
            for (var e = 0; e < eVals.length; e++) {
              var v = String(eVals[e][0]).trim();
              if (v && v !== "") entities.add(v);
            }
            setText("info-entities", entities.size > 0 ? entities.size : "—");
          });
        } else {
          setText("info-entities", "—");
        }
      });
    });
  }).catch(function () {
    setText("info-scenario", "—");
    setText("info-type", "—");
    setText("info-year", "—");
    setText("info-layer", "—");
    setText("info-entities", "—");
    setText("info-rows", "—");
  });
}

// ── Budget: Scan Sheet ──────────────────────────────────────────
function scanSheet(context) {
  var sheet = context.workbook.worksheets.getActiveWorksheet();

  // Read info block (rows 1-7, cols A-B)
  var infoRange = sheet.getRange("A1:B7");
  infoRange.load("values");

  // Read header area to find header row
  var headerScan = sheet.getRange("A1:A20");
  headerScan.load("values");

  var usedRange = sheet.getUsedRange();
  usedRange.load("rowCount");

  return context.sync().then(function () {
    // Parse info block
    var info = infoRange.values;
    var fiscalYear = 2024;
    var layer = "base";
    var scenarioId = "";

    for (var r = 0; r < info.length; r++) {
      var label = String(info[r][0]).trim().toUpperCase();
      var val = info[r][1];
      if (label === "FISCAL YEAR:" && val) fiscalYear = Number(val);
      else if (label === "LAYER:") layer = String(val).trim();
      else if (label === "SCENARIO ID:") scenarioId = String(val).trim();
    }

    // Find header row
    var headerRow = -1;
    var hVals = headerScan.values;
    for (var i = 0; i < hVals.length; i++) {
      if (String(hVals[i][0]).trim().toUpperCase() === "SCENARIO ID") {
        headerRow = i; // 0-based
        break;
      }
    }

    if (headerRow < 0) {
      return { rows: [], fiscalYear: fiscalYear, layer: layer, error: "No header row found" };
    }

    var lastRow = usedRange.rowCount;
    var dataStartRow = headerRow + 2; // 1-based Excel row
    if (dataStartRow > lastRow) {
      return { rows: [], fiscalYear: fiscalYear, layer: layer };
    }

    // Read data: cols A-H (metadata) + I-T (periods 1-12)
    var dataRange = sheet.getRange(
      "A" + dataStartRow + ":T" + lastRow
    );
    dataRange.load("values");

    return context.sync().then(function () {
      var rows = [];
      var data = dataRange.values;

      for (var r = 0; r < data.length; r++) {
        var rowScenario = String(data[r][0]).trim(); // Col A
        var entity = String(data[r][1]).trim();       // Col B
        var account = String(data[r][3]).trim();       // Col D
        var costCenter = String(data[r][6]).trim();    // Col G
        var department = String(data[r][7]).trim();    // Col H

        // Skip empty/separator/total rows
        if (!rowScenario || !account || !entity) continue;
        // Skip if scenario looks like a label (entity separator rows)
        if (rowScenario === entity && !account) continue;

        var periods = [];
        for (var p = 8; p < 20; p++) { // Cols I-T = indices 8-19
          var val = data[r][p];
          periods.push(typeof val === "number" ? val : (parseFloat(val) || 0));
        }

        rows.push({
          scenario_id: rowScenario || scenarioId,
          entity: entity,
          account: account,
          cost_center: costCenter,
          department: department,
          fiscal_year: fiscalYear,
          layer: layer,
          periods: periods
        });
      }

      return { rows: rows, fiscalYear: fiscalYear, layer: layer };
    });
  });
}

// ── Budget: Save ────────────────────────────────────────────────
function showBudgetStatus(msg, type) {
  var el = document.getElementById("budget-status");
  el.textContent = msg;
  el.className = "status-area" + (type ? " status-" + type : "");
  el.hidden = false;
}

function saveBudget() {
  hideError("budget-error");
  hide("budget-status");
  showBudgetStatus("Scanning sheet\u2026", "info");

  Excel.run(function (context) {
    return scanSheet(context);
  }).then(function (result) {
    if (result.error) {
      showBudgetStatus(result.error, "error");
      return;
    }
    if (result.rows.length === 0) {
      showBudgetStatus("No data rows found.", "error");
      return;
    }

    showBudgetStatus("Saving " + result.rows.length + " rows\u2026", "info");

    // Build batch payload
    var entries = [];
    for (var i = 0; i < result.rows.length; i++) {
      var row = result.rows[i];
      for (var p = 0; p < 12; p++) {
        if (row.periods[p] === 0) continue; // skip zero amounts
        entries.push({
          scenario_id: row.scenario_id,
          entity: row.entity,
          account: row.account,
          fiscal_year: row.fiscal_year,
          period: p + 1,
          amount: row.periods[p],
          layer: row.layer,
          cost_center: row.cost_center || "",
          department: row.department || ""
        });
      }
    }

    return fetch(FRAPPE_URL + "/api/method/konsol.api.budget_save_batch", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      credentials: "include",
      body: JSON.stringify({ entries: entries })
    }).then(function (res) {
      if (!res.ok) throw new Error("Save failed (HTTP " + res.status + ")");
      return res.json();
    }).then(function (data) {
      var saved = (data.message && data.message.saved) || entries.length;
      showBudgetStatus("Saved " + saved + " entries.", "");
    });
  }).catch(function (err) {
    showBudgetStatus("Error: " + err.message, "error");
  });
}

function saveBudgetAll() {
  hideError("budget-error");
  hide("budget-status");
  showBudgetStatus("Saving all sheets\u2026", "info");

  Excel.run(function (context) {
    var sheets = context.workbook.worksheets;
    sheets.load("items/name");
    return context.sync().then(function () {
      return sheets.items;
    });
  }).then(function (sheetItems) {
    var sheetNames = [];
    for (var i = 0; i < sheetItems.length; i++) {
      var name = sheetItems[i].name;
      if (name !== "Setup" && name !== "_EPM_Log") {
        sheetNames.push(name);
      }
    }

    var totalSaved = 0;
    var idx = 0;

    function saveNext() {
      if (idx >= sheetNames.length) {
        showBudgetStatus("Saved " + totalSaved + " entries across " + sheetNames.length + " sheets.", "");
        return;
      }

      var sheetName = sheetNames[idx];
      showBudgetStatus("Saving sheet " + (idx + 1) + "/" + sheetNames.length + ": " + sheetName + "\u2026", "info");

      return Excel.run(function (context) {
        var sheet = context.workbook.worksheets.getItem(sheetName);
        sheet.activate();
        return context.sync().then(function () {
          return scanSheet(context);
        });
      }).then(function (result) {
        if (!result.rows || result.rows.length === 0) {
          idx++;
          return saveNext();
        }

        var entries = [];
        for (var i = 0; i < result.rows.length; i++) {
          var row = result.rows[i];
          for (var p = 0; p < 12; p++) {
            if (row.periods[p] === 0) continue;
            entries.push({
              scenario_id: row.scenario_id,
              entity: row.entity,
              account: row.account,
              fiscal_year: row.fiscal_year,
              period: p + 1,
              amount: row.periods[p],
              layer: row.layer,
              cost_center: row.cost_center || "",
              department: row.department || ""
            });
          }
        }

        return fetch(FRAPPE_URL + "/api/method/konsol.api.budget_save_batch", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "include",
          body: JSON.stringify({ entries: entries })
        }).then(function (res) {
          if (!res.ok) throw new Error("Save failed for " + sheetName);
          return res.json();
        }).then(function (data) {
          var saved = (data.message && data.message.saved) || entries.length;
          totalSaved += saved;
          idx++;
          return saveNext();
        });
      });
    }

    return saveNext();
  }).catch(function (err) {
    showBudgetStatus("Error: " + err.message, "error");
  });
}

// ── Budget: Refresh Actuals ─────────────────────────────────────
function refreshSheet() {
  hideError("budget-error");
  hide("budget-status");
  showBudgetStatus("Reading sheet\u2026", "info");

  Excel.run(function (context) {
    var sheet = context.workbook.worksheets.getActiveWorksheet();

    // Read info block
    var infoRange = sheet.getRange("A1:B7");
    infoRange.load("values");

    // Find header row
    var headerScan = sheet.getRange("A1:A20");
    headerScan.load("values");

    var usedRange = sheet.getUsedRange();
    usedRange.load("rowCount");

    return context.sync().then(function () {
      var info = infoRange.values;
      var fiscalYear = 2024;

      for (var r = 0; r < info.length; r++) {
        var label = String(info[r][0]).trim().toUpperCase();
        if (label === "FISCAL YEAR:" && info[r][1]) {
          fiscalYear = Number(info[r][1]);
        }
      }

      var headerRow = -1;
      var hVals = headerScan.values;
      for (var i = 0; i < hVals.length; i++) {
        if (String(hVals[i][0]).trim().toUpperCase() === "SCENARIO ID") {
          headerRow = i;
          break;
        }
      }

      if (headerRow < 0) {
        showBudgetStatus("No header row found on this sheet.", "error");
        return;
      }

      var lastRow = usedRange.rowCount;
      var dataStartRow = headerRow + 2;

      // Read metadata columns (A-H) for each data row
      var metaRange = sheet.getRange("A" + dataStartRow + ":H" + lastRow);
      metaRange.load("values");

      return context.sync().then(function () {
        var meta = metaRange.values;
        var queries = [];

        for (var r = 0; r < meta.length; r++) {
          var scenario = String(meta[r][0]).trim();
          var entity = String(meta[r][1]).trim();
          var account = String(meta[r][3]).trim();

          if (!scenario || !entity || !account) continue;

          for (var p = 1; p <= 12; p++) {
            queries.push({
              entity: entity,
              fiscal_year: fiscalYear,
              period: p,
              account: account,
              measure: "amount",
              scenario: "actual"
            });
          }
        }

        if (queries.length === 0) {
          showBudgetStatus("No data rows to refresh.", "error");
          return;
        }

        showBudgetStatus("Fetching " + queries.length + " values\u2026", "info");

        return fetch(FRAPPE_URL + "/api/method/konsol.api.epm_batch", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          credentials: "include",
          body: JSON.stringify({ queries: queries })
        }).then(function (res) {
          if (!res.ok) throw new Error("Refresh failed (HTTP " + res.status + ")");
          return res.json();
        }).then(function (data) {
          var results = data.message || [];

          // Write values back to cells I-T
          return Excel.run(function (ctx) {
            var ws = ctx.workbook.worksheets.getActiveWorksheet();
            var metaR = ws.getRange("A" + dataStartRow + ":H" + lastRow);
            metaR.load("values");

            return ctx.sync().then(function () {
              var m = metaR.values;
              var resultIdx = 0;

              for (var r = 0; r < m.length; r++) {
                var scenario = String(m[r][0]).trim();
                var entity = String(m[r][1]).trim();
                var account = String(m[r][3]).trim();

                if (!scenario || !entity || !account) continue;

                // This row has 12 results
                for (var p = 0; p < 12; p++) {
                  if (resultIdx < results.length) {
                    var val = results[resultIdx].value;
                    if (val !== null && val !== undefined) {
                      var cellAddr = String.fromCharCode(73 + p) + (dataStartRow + r); // I=73
                      ws.getRange(cellAddr).values = [[val]];
                    }
                    resultIdx++;
                  }
                }
              }

              return ctx.sync();
            });
          }).then(function () {
            showBudgetStatus("Refreshed " + results.length + " values.", "");
            updateSheetInfo();
          });
        });
      });
    });
  }).catch(function (err) {
    showBudgetStatus("Error: " + err.message, "error");
  });
}
