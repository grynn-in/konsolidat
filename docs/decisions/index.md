---
title: Decision records
sidebar_label: Overview
description: Decision briefs for the open issues of the 2026-07-01 triage, with the options weighed, the recommendation, and what the code shows as of 2026-11-05.
---

# Decision records

Decision briefs for every open issue as of the 2026-07-01 triage — the options
considered and the recommended path. Each links to its GitHub issue. Format:
Context → Options (with trade-offs) → **Recommendation** → Consequences.

:::note Provenance
The twelve briefs were written in the konsolidat repository (`docs/developer-guide/decisions/`, commit `1ccafa9`, 2 July 2026) and ported to this site on 2026-11-05. They are **recommendations by their author, not decisions by Deepak Pai**, except where a page says so and cites the pull requests (konsolidat #93, decided 13 Sep 2026). Their text is kept as written; each page carries a "Status as of 2026-11-05" section that states what the code shows now, with the file or commit that shows it. Where a retired doctype name appeared, the current name is used and the rename commit is cited.
:::

| Issue | Topic | Recommendation (2026-07-01, one line) | Status as of 2026-11-05 |
|---|---|---|---|
| konsolidat #93 | [Consolidation currency](konsolidat-93-consolidation-currency.md) | **Decided 13 Sep 2026:** currency on each Consolidation Group node (validated Link), EPM Settings field removed, governed rates per period; Phase 2 deferred | Holds in code: `reporting_currency` Link on Consolidation Group; Group Exchange Rate doctype; dbt reads `epm_staging.group_exchange_rates` only |
| konsolidat #130 | [Membership divergence](konsolidat-130-membership-divergence.md) | **Align to the seed** (GROUP_CORP) + generate seed from the doctype — needs owner sign-off | Seeds deleted (`85dff3b`); the table is konsol-owned; HER records re-keyed by patch; multi-level groups now walk the tree; pair check still off; no owner sign-off recorded |
| konsolidat #92 | [Historical Equity Rate — remaining](konsolidat-92-historical-equity-rate.md) | Add an **is-equity guard via a synced account cache**; pair-check after #130 | Guard exists on both sides (Main Account `fx_method` + konsol#239; `assert_historical_is_equity_only`); pair check still open |
| konsolidat #91 | [Surface FX rates](konsolidat-91-surface-fx.md) | **Part B first** (read-only CH view); Part C (manual doctype) later | Superseded 13 Sep 2026 by governed Group Exchange Rates; read API `get_fx_rates` and the `/close` Rates screen show them |
| konsolidat #131 | [Asset self-heal staleness](konsolidat-131-selfheal-staleness.md) | **Hash-guard + timeout** the heal | **Done** the same day (`166519a`, `docker/frappe/refresh-assets.sh`) |
| konsolidat #90 | [Productionize Airbyte](konsolidat-90-airbyte-prod.md) | Defer (P2); when needed, **Helm Airbyte on real k8s** | Unchanged: `abctl`/kind (`scripts/setup-airbyte.sh`) |
| konsolidat #57 | [ClickHouse cluster mode](konsolidat-57-clickhouse-cluster.md) | Defer (scale-gated); prefer **managed CH or Keeper+shards** when scale lands | Unchanged: single-node; cluster files untouched since June; 11 models carry the opt-in macros |
| konsol #56 | [Orchestrator epic](konsol-56-orchestrator-epic.md) | Keep as tracker; roadmap P2 → P3 | Orchestrator package built; the konsol-exec UI it served was removed (konsol#305); runs start from the Desk |
| konsol #58 | [Orchestrator P2](konsol-58-orchestrator-p2.md) | **Scheduler execution first**, then definitions editor, then resume UX | Scheduler built (`cron.run_due_schedules`, every minute); resume core built, UI gone; definitions via the Pipeline form |
| konsol #59 | [Orchestrator P3](konsol-59-orchestrator-p3.md) | Lowest priority; do **FX surfacing + basic lineage view** | FX API built over governed rates; lineage/resources are pure-python cores without a view |
| konsol #74 | [Orchestrator hardening](konsol-74-orchestrator-hardening.md) | Fold into P2; **planning-wedge guard first** | Reaper and run-level wedge guard exist; a planning-phase guard and the "nothing to do" status were not identified by name |
| konsol #55 | [Past-FY consolidation close](konsol-55-past-fy-close.md) | **Wire the FY selector through the close path**; do with P2 | Moot: konsol-exec removed; `run_checks(fiscal_year, fiscal_period)` and the Period Close Desk report take the period from the user |

_The 2026-07-01 briefs are recommendations, not commitments — the "needs sign-off" items (esp. #130) change reported numbers and want a deliberate call._ Whether each GitHub issue is open or closed was not checked from the machine that ported these pages; the status column reports code, not issue state.

Related design pages: [konsol-exec as a pipeline orchestrator](https://docs.konsolidat.com/developer-guide/design/konsol-exec-orchestrator), [Multi-ERP consolidation](https://docs.konsolidat.com/developer-guide/design/multi-erp-consolidation), [Business combinations](https://docs.konsolidat.com/developer-guide/design/business-combinations), [Entity close and reconciliation](https://docs.konsolidat.com/developer-guide/design/entity-close-and-reconciliation).
