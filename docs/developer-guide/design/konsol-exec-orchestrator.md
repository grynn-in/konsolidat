# Design — konsol-exec as a Pipeline Orchestrator

**Status:** Proposed · **Scope:** konsol app (`konsol-exec` SPA + `control_api.py` + pipeline doctypes) · **Related:** konsol#55 (year selector), konsolidat#91 (FX surfacing), konsolidat#109/#110/#111 (data-quality follow-ups)

> **Naming updated 2026-07:** the doctypes proposed here shipped and were then renamed — "Pipeline Definition" is now the **Pipeline** doctype, its template steps are **Pipeline Step** (formerly "Step Definition"), and the per-run execution rows are **Run Step**. "Close Run" → **Period Close** → **Assertion Run** (it runs the close-assertion suite; it does not close entities). This doc uses the current names.

## Context

The data platform runs a real pipeline: **D365 → Airbyte → ClickHouse `epm_raw` → dbt (staging→bronze→silver→gold) → consolidation/close → Cube/Excel**. But `konsol-exec` today is a *launcher*, not an *orchestrator*: four hardcoded process cards (`PROCESSES` = budgeting / forecasting / consolidation / assertions) — budgeting/forecasting/consolidation route through `run_governed_build` (via `build_scope`), close/assertions through `trigger_close_run` — each firing **one** backend function and streaming a single log. There is:

- no decomposition into **steps** (you can't see or control extract vs transform vs test);
- no **parameters** (can't pick fiscal year/period — #55 — or `dbt run` vs `build`, `--full-refresh`, scope, skip-sync);
- no **retry / resume / cancel**, no per-step logs, no lineage;
- no **scheduling**;
- a binary **preflight** instead of a real readiness model.

Bringing up real D365 data this cycle required a dozen server-side workarounds (set connector `last_sync_at`, `dbt run` instead of governed `build`, `--full-refresh` to clear stale incremental rows, `trigger_close_run(2024,12)` by hand). **Every one of those should be a UI-driven step or parameter.**

This doc proposes turning `konsol-exec` into a first-class orchestrator modeled on **Airbyte** (connections + jobs/attempts + logs), **Frappe Press** (stepped builds with live-streamed output, retryable), and **Dagster/Airflow** (a DAG of typed tasks with params, schedules, retries, run history, lineage). The common shape they all share — and the thing we're missing — is:

> **A Run is a DAG of typed Steps, each independently observable, retryable, and parameterized.**

## Architecture

### Data model (Frappe doctypes)

```
Pipeline             (the DAG template)
   └─< Pipeline Step         type · depends_on · default params

Pipeline Run         (one execution = pipeline + run params)
   ├─ params:  fiscal_year · fiscal_period · scope · full_refresh · skip_sync
   └─< Run Step               type · status · depends_on · params
                              · log · started_at · ended_at · rows · retry_count

Resource  ──  Airbyte Connection | dbt Project | ClickHouse Target
              (formalizes what is scattered in EPM Settings today)
```

| Doctype | Role | Status today |
|---|---|---|
| **Pipeline** | DAG template: ordered steps + dependencies + default params | new |
| **Pipeline Run** | run aggregate + params | exists, thin → promoted |
| **Run Step** | per-step status/logs/deps/retry/params | **new — the missing core** |
| **Resource / Connection** | Airbyte conn, dbt project, CH target | scattered → formalized |

### Step-type library

Each step type is a handler the executor knows how to run and stream. dbt steps take `select`/`exclude`, **`full_refresh`**, and `vars` — so run-vs-build, full-refresh, scope and fiscal year stop being special cases and become **step parameters**.

```
airbyte_sync   dbt_seed   dbt_run   dbt_build   dbt_test
close_assertions   signoff(gate)   cube_refresh   sql / script
```

### The pipeline as a DAG

```
   extract            transform                          validate          surface
 ┌──────────┐   ┌──────────────────────────────┐   ┌───────────────┐   ┌──────────┐
 │ airbyte  │──▶│ seed → staging → bronze       │──▶│    close      │──▶│   cube   │
 │  sync    │   │      → silver → gold          │   │  assertions   │   │ refresh  │
 └──────────┘   └──────────────────────────────┘   └──────┬────────┘   └──────────┘
   writes back                                            │
   last_sync_at                                      ┌─────▼──────┐
                                                     │  sign-off  │  (manual gate)
                                                     └────────────┘
```

### Executor

A worker process (`konsol.orchestrator.run`) that:
1. resolves the Run's DAG from its Pipeline + params,
2. walks steps in dependency order, running each handler in a subprocess (dbt) or client (Airbyte),
3. checkpoints each Run Step's status and streams logs via `frappe.publish_realtime`,
4. supports **resume-from-step**, **retry-failed-step**, **cancel**, and a **per-scope concurrency lock** (today's binary guard in `trigger_close_run` generalized),
5. is idempotent per (definition, params) so a re-run is safe.

### Control plane (the SPA)

```
┌─ Konsol Exec ────────────────────────────────────────────────────┐
│ Pipeline: Group Close     FY 2024 ▾  Period 12 ▾      [ Run ▸ ]   │
│ Options:  ☑ full-refresh   ☐ skip sync   scope: consolidation ▾   │
├───────────────────────────────────────────────────────────────────┤
│ Run PRUN-00042      ● Running     started 12:04      ⟳ 00:42       │
│                                                                   │
│   ① Extract     · airbyte_sync        ✓ 6.2s   511,789 rows       │
│   ② Seed        · dbt_seed            ✓ 1.1s                      │
│   ③ Transform   · dbt_run (silver)    ● running  ▓▓▓▓▓░░  04:12    │
│   ④ Gold        · dbt_run (gold)      ◷ pending                   │
│   ⑤ Assertions  · close_assertions    ◷ pending                  │
│   ⑥ Sign-off    · signoff (gate)      ◷ pending                  │
│                                                                   │
│  ┌ Step ③ log ────────────────────────────── [retry] [skip] ──┐  │
│  │ 12:06  11 of 34 OK   silver_gl_entries ......... [OK 4.1s]  │  │
│  │ 12:06  12 of 34 START silver_exchange_rates ...             │  │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  History:  PRUN-00041 ✓ Green · PRUN-00040 ✗ Red(step⑤) · …       │
└───────────────────────────────────────────────────────────────────┘
```

- **Param form** to launch (year/period/scope/flags) → kills #55.
- **DAG / timeline** with per-step status + **live per-step logs** (the Press "build steps" view, for real — `period_close.js` already aspires to this).
- **Retry / resume / cancel** per step; **run history**; **schedules** (Frappe Scheduler cron); **Connections** management view.

## How this subsumes the current gaps

| Manual workaround this cycle | Becomes |
|---|---|
| `trigger_close_run(2024,12)` server-side | a run **param** (fiscal year/period) — #55 |
| `dbt run` instead of governed `dbt build` | a **step type** choice (`dbt_run` vs `dbt_build`) |
| `--full-refresh` to clear stale bronze | a **step param** (`full_refresh`) |
| set `Connector.last_sync_at` by hand | the `airbyte_sync` step **writes it back** |
| scope selection (`+tag:domain:consolidation`) | a **step param** (`select`) |
| read TB/close failures from the DB | per-step **results + sample rows** in the UI |
| FX rate visibility/entry (#91 B/C) | a **surface** step + a Resource view |

**Out of scope (intentionally):** editing dbt SQL and opening PRs — that is code/Git work, not an ops console. Data fixes flow through the repo.

## Reuse vs build · build-vs-buy

- **Reuse:** Airbyte itself (extract); the existing `_run_airbyte_sync` / `_run_dbt_build` / `run_close_assertions` logic (refactored into step handlers); the XState SPA + the `*_update` realtime channel; Frappe permissions/audit/scheduler.
- **Build:** the **Run Step** doctype, the **DAG executor**, and the **param/timeline UI**.
- **Build-vs-buy:** stay **native** (Frappe doctypes + worker + the existing SPA). Bolting on Dagster/Airflow would fight the single-container deployment and forfeit Frappe's permissions / realtime / sign-off / audit. Dagster is the *conceptual* reference, not a dependency.

## Phasing

- **P1 — Step engine over the existing pipeline.** Run Step + executor; decompose today's sync→dbt→close into visible, retryable, parameterized steps with live logs (year/period/scope/full-refresh/skip-sync). Unifies the three buttons and delivers ~all the missing control. *Highest value.*
- **P2 — Editable Pipelines, schedules, resume-from-step.** DAG authoring; cron triggers; restart a failed run from any step.
- **P3 — Lineage/metrics, Connection-management UI, FX surfacing (#91 B/C), multi-ERP.** Per-step row/duration metrics + lineage; managed resources; surface gold/FX; multiple ERP sources.

## Acceptance (P1)

From `konsol-exec`, a user can launch a Group Close for **any** fiscal year/period, watch it run as discrete steps with live logs, **retry or resume from a failed step**, choose `dbt run`/`build` + `full_refresh` + scope, and have the Airbyte step record its own sync status — with **zero** server-side intervention.
