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
  hide("status-section");
}

function showStatusView(user) {
  hide("login-section");
  show("status-section");
  setText("user-label", user);
  loadPipelineStatus();
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
