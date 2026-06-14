/* global CustomFunctions, fetch */

// ============================================================
// Open EPM — Excel Custom Functions  (namespace "K")
// ============================================================
//
// Live, auto-recalculating worksheet functions that COMPLEMENT the VBA
// in excel/OpenEPM.bas (which stays in place for demos). Unlike the VBA
// — which returns 0 until a manual Refresh — these fetch on their own and
// debounce every pending cell into ONE konsol.api.epm_batch POST.
//
//   =K.EPM(entity, year, period, account, [measure], [scenario],
//          [costCenter], [department], [scenarioId])
//   =K.EPM_BUDGET / EPM_VARIANCE / EPM_DEBIT / EPM_CREDIT
//   =K.EPMSAVE(amount, entity, year, period, account, scenarioId, layer,
//              [costCenter], [department])
//
// Served same-origin by Frappe at /assets/konsol/excel-addin/, so all
// requests use relative paths + credentials:"include" — no CORS.
// ============================================================

// Backend caps a batch at 2000; keep margin under it.
var MAX_BATCH = 2000;

// ── Read batcher ────────────────────────────────────────────
// Queue of { req, resolve, reject } awaiting the next flush.
var pending = [];
var flushScheduled = false;

function enqueue(req) {
  return new Promise(function (resolve, reject) {
    pending.push({ req: req, resolve: resolve, reject: reject });
    if (!flushScheduled) {
      flushScheduled = true;
      // One-tick debounce: coalesce all cells recalculated in this pass.
      Promise.resolve().then(flush);
    }
  });
}

function flush() {
  flushScheduled = false;
  var batch = pending;
  pending = [];
  if (batch.length === 0) return;

  // Chunk to respect MAX_BATCH.
  for (var i = 0; i < batch.length; i += MAX_BATCH) {
    sendChunk(batch.slice(i, i + MAX_BATCH));
  }
}

function sendChunk(chunk) {
  var body = chunk.map(function (e) { return e.req; });

  fetch("/api/method/konsol.api.epm_batch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify(body)
  }).then(function (res) {
    if (res.status === 401 || res.status === 403) {
      throw new CustomFunctions.Error(
        CustomFunctions.ErrorCode.notAvailable,
        "Not logged in — open the Open EPM task pane and sign in."
      );
    }
    if (!res.ok) {
      throw new CustomFunctions.Error(
        CustomFunctions.ErrorCode.notAvailable,
        "epm_batch failed (HTTP " + res.status + ")"
      );
    }
    return res.json();
  }).then(function (data) {
    // Frappe wraps the return value in `message`: { values:[...], errors:[...]? }.
    var payload = (data && data.message) || {};
    var values = payload.values || [];
    var errors = payload.errors || [];

    chunk.forEach(function (e, idx) {
      var err = errors[idx];
      if (err) {
        e.reject(new CustomFunctions.Error(
          CustomFunctions.ErrorCode.invalidValue, String(err)
        ));
        return;
      }
      var v = values[idx];
      e.resolve(v === null || v === undefined ? 0 : v);
    });
  }).catch(function (err) {
    // Reject every cell in this chunk with the same error.
    chunk.forEach(function (e) {
      e.reject(err instanceof CustomFunctions.Error ? err :
        new CustomFunctions.Error(CustomFunctions.ErrorCode.notAvailable, String(err && err.message || err)));
    });
  });
}

// Build one epm_batch request object. Empty optionals are omitted so the
// backend applies its own defaults.
function makeReq(entity, year, period, account, measure, scenario, costCenter, department, scenarioId) {
  var req = {
    entity: String(entity),
    year: Number(year),
    period: period,                 // backend accepts 1-12 or Q1/H1/FY strings
    account: String(account)
  };
  if (measure) req.measure = String(measure);
  if (scenario) req.scenario = String(scenario);
  if (costCenter) req.cost_center = String(costCenter);
  if (department) req.department = String(department);
  if (scenarioId) req.scenario_id = String(scenarioId);
  return req;
}

// ── Read functions ──────────────────────────────────────────
function epm(entity, year, period, account, measure, scenario, costCenter, department, scenarioId) {
  return enqueue(makeReq(entity, year, period, account, measure, scenario, costCenter, department, scenarioId));
}

function epmBudget(entity, year, period, account, costCenter, department, scenarioId) {
  return enqueue(makeReq(entity, year, period, account, "period_amount", "budget", costCenter, department, scenarioId));
}

function epmVariance(entity, year, period, account, costCenter, department, scenarioId) {
  return enqueue(makeReq(entity, year, period, account, "variance_abs", "variance", costCenter, department, scenarioId));
}

function epmDebit(entity, year, period, account, costCenter, department) {
  return enqueue(makeReq(entity, year, period, account, "period_debit", "actuals", costCenter, department, ""));
}

function epmCredit(entity, year, period, account, costCenter, department) {
  return enqueue(makeReq(entity, year, period, account, "period_credit", "actuals", costCenter, department, ""));
}

// ── Write function ──────────────────────────────────────────
// Immediate write-back on recalc. Returns `amount` so the cell shows it.
function epmSave(amount, entity, year, period, account, scenarioId, layer, costCenter, department) {
  var data = {
    scenario_id: String(scenarioId),
    data_area_id: String(entity),
    fiscal_year: Number(year),
    main_account: String(account),
    fiscal_period: Number(period),
    amount: Number(amount),
    layer: String(layer)
  };
  if (costCenter) data.dim_cost_center = String(costCenter);
  if (department) data.dim_department = String(department);

  return fetch("/api/method/konsol.api.budget_cell_save", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify(data)
  }).then(function (res) {
    if (res.status === 401 || res.status === 403) {
      throw new CustomFunctions.Error(
        CustomFunctions.ErrorCode.notAvailable,
        "Not logged in — open the Open EPM task pane and sign in."
      );
    }
    if (!res.ok) {
      throw new CustomFunctions.Error(
        CustomFunctions.ErrorCode.invalidValue,
        "Save failed (HTTP " + res.status + ")"
      );
    }
    return Number(amount);
  });
}

// ── Registration ────────────────────────────────────────────
// IDs must match functions.json; the "K" namespace comes from the manifest.
CustomFunctions.associate("EPM", epm);
CustomFunctions.associate("EPM_BUDGET", epmBudget);
CustomFunctions.associate("EPM_VARIANCE", epmVariance);
CustomFunctions.associate("EPM_DEBIT", epmDebit);
CustomFunctions.associate("EPM_CREDIT", epmCredit);
CustomFunctions.associate("EPMSAVE", epmSave);
