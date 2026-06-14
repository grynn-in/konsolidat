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
// requests use relative paths + credentials:"include" — no CORS. Auth relies
// on the session cookie set when the user signs in via the task pane; the
// manifest declares a SHARED RUNTIME so that cookie is visible here (the
// JS-only custom-functions runtime does not support cookies).
// ============================================================

// Same-origin: served by Frappe, so no base URL needed (mirrors taskpane.js).
var FRAPPE_URL = "";

// Backend caps a batch at 2000; keep margin under it.
var MAX_BATCH = 2000;

// ── HTTP helper (shared by reads and writes) ────────────────
// POST JSON to a konsol endpoint and resolve the parsed Frappe response body,
// or throw a CustomFunctions.Error for auth/HTTP failures.
function postJson(path, body) {
  return fetch(FRAPPE_URL + path, {
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
        "Request failed (HTTP " + res.status + ")"
      );
    }
    return res.json();
  });
}

// ── Read batcher ────────────────────────────────────────────
// Queue of { req, resolve, reject } awaiting the next flush.
var pending = [];
var flushScheduled = false;

function enqueue(req) {
  return new Promise(function (resolve, reject) {
    // Guard a non-numeric year HERE. NaN would serialize to JSON null, and the
    // backend's int(year) is outside its per-cell try/except, so it raises an
    // unhandled error that 500s the WHOLE batch — poisoning every other cell in
    // the chunk. Failing just this one cell keeps its siblings working.
    if (!isFinite(req.year)) {
      reject(new CustomFunctions.Error(
        CustomFunctions.ErrorCode.invalidValue, "Invalid year"
      ));
      return;
    }
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

  postJson("/api/method/konsol.api.epm_batch", body).then(function (data) {
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
// Tracks the last successfully-saved value per cell key so an unchanged cell
// is not re-POSTed on every recalc. Mirrors the VBA's pSaveCache; without it,
// a volatile custom function re-saves every budget cell on each recalc.
var saveCache = {};

// Immediate write-back on recalc. Returns `amount` so the cell shows it.
function epmSave(amount, entity, year, period, account, scenarioId, layer, costCenter, department) {
  var amt = Number(amount);

  // Bad inputs → surface an error rather than POSTing garbage.
  if (!isFinite(amt) || !isFinite(Number(year)) || !isFinite(Number(period))) {
    throw new CustomFunctions.Error(
      CustomFunctions.ErrorCode.invalidValue, "Invalid EPMSAVE arguments"
    );
  }

  var key = [scenarioId, entity, year, period, account, layer,
             costCenter || "", department || ""].join("|");
  // Skip the POST if this exact cell+value was already saved — prevents a
  // write-storm where every recalc re-writes unchanged budget cells.
  if (saveCache[key] === amt) {
    return amt;
  }

  var data = {
    scenario_id: String(scenarioId),
    data_area_id: String(entity),
    fiscal_year: Number(year),
    main_account: String(account),
    fiscal_period: Number(period),
    amount: amt,
    layer: String(layer)
  };
  if (costCenter) data.dim_cost_center = String(costCenter);
  if (department) data.dim_department = String(department);

  return postJson("/api/method/konsol.api.budget_cell_save", data).then(function () {
    saveCache[key] = amt;   // remember success so we don't re-POST it
    return amt;
  }).catch(function () {
    // Best-effort write, matching the VBA: keep displaying the typed value
    // instead of replacing it with #VALUE!. Not cached, so the next recalc
    // retries the failed save.
    return amt;
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
