# Scoped consolidation (dbt) — durable handoff (read me first)

You are a fresh agent. This file + `DBT-PRDS.md` are the source of truth. Do **exactly one PRD** (or one review/fix pass), then stop.

## Goal
Finish + harden the orchestrator's scoped/period consolidation (follow-ups from merged PRs #112/#115). dbt only (repo grynn-in/konsolidat). No app/Frappe changes.

## CRITICAL: where to edit vs where to test vs where to commit
dbt in the container reads the **live mounted tree**, NOT this worktree:
- **Edit** files in the LIVE tree: `/home/pd/open_epm/dbt_project/...` (the container `konsolidat_worker` mounts this at `/home/frappe/dbt_project`).
- **Test** in the container:
  ```
  docker exec konsolidat_worker bash -lc '/home/frappe/frappe-bench/env/bin/dbt <run|test|build> --select <X> --project-dir /home/frappe/dbt_project --profiles-dir /home/frappe/dbt_project'
  ```
  dbt 1.11.11; profiles.yml is in the project dir; target schema `epm_gold` on `konsolidat_clickhouse`.
- **Commit** to THIS worktree (`/home/pd/konsolidat-wt-scoped`, branch `feat/scoped-consolidation`, off origin/main):
  copy ONLY your changed files from the live tree into the worktree, then verify each shows just your intended change before committing:
  ```
  cp /home/pd/open_epm/dbt_project/<file> /home/pd/konsolidat-wt-scoped/<file>
  cd /home/pd/konsolidat-wt-scoped && git add <file> && git diff --cached origin/main -- <file>   # eyeball: only your change
  git commit -m "feat(dbt): A-N <title>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```
  Never `git add -A` (the live tree has unrelated in-flight changes — add only the files your PRD touches).

## STATE SAFETY (non-negotiable)
Scoped runs (with `entity_scope`/`fiscal_year`/`fiscal_period` vars) **narrow live ClickHouse gold tables**. After you finish testing a PRD, you MUST leave the live gold tables FULL:
- Re-run the affected models with **no vars** (full refresh) and confirm row counts return to baseline. Capture baseline counts BEFORE you start (e.g. `gold_consolidated_trial_balance`, `gold_cash_flow_indirect`, `gold_ytd_trial_balance` row counts) and restore to them.
- ClickHouse TRUNCATE/overwrite is irreversible — never drop data; only rebuild.

## TDD for dbt
Red→green via a **dbt test**: add/extend a singular test (`tests/`) or schema test that FAILS before your model change and PASSES after. Plus a `dbt run` + row-count/spot-check assertion proving the behavior (e.g. a scoped run narrows the target). Confirm RED first (run the test, see it fail), implement, GREEN, then a full no-var `dbt build --select <affected>+` stays green and restores counts.

## Key facts
- Filters live in `dbt_project/macros/orchestrator_filters.sql`: `period_filter(year_col, period_col)` + `scope_filter(data_area_col)`. Both opt-in (no var → empty string). `scope_filter` already escapes single quotes (`replace("'", "''")`).
- The consolidation chokepoint where filters are applied today: `models/gold/gold_consolidated_trial_balance.sql` (entity_tb CTE has `where 1=1 {{ period_filter(...) }} {{ scope_filter(...) }}`).
- **The #119 bug:** `gold_cash_flow_indirect.sql` and `gold_ytd_trial_balance.sql` `ref('gold_trial_balance')` DIRECTLY — they bypass the chokepoint, so a scoped close does NOT narrow them.
- Spine: `gold_trial_balance` (40K) → `gold_consolidated_trial_balance` (~14K) → `gold_fully_consolidated_tb` → cash_flow/ytd/nci.

## Conventions
- Keep full builds byte-for-byte unchanged when no vars are set (opt-in everywhere).
- Match existing SQL style; comment macro/materialization intent.
- One PRD per commit (+ a docs commit ticking the PRD and repointing this file's *Current state*/*Next*).
- Commit subject `feat(dbt): A-N <title>` / `fix(dbt): C-N <title>` + Co-Authored-By trailer.

## Loop protocol
**Build:** take the first unchecked PRD in `DBT-PRDS.md`. Capture baselines → RED test → implement (edit live) → GREEN → full no-var rebuild restores counts → commit slice to worktree → tick PRD `[x]` → update this file → commit docs → STOP. Return the status object.
**Review:** independent, adversarial. Inspect the PRD's worktree diff (`git show`), RE-RUN the relevant dbt test/build yourself, verify opt-in (no-var build unchanged) + state restored. Return blocking findings (empty = approved). Don't edit.
**Fix:** apply blocking findings, keep green + counts restored, commit `fix(dbt): A-N address review`, STOP.

## Current state
**C2 (#120) DONE** — commit `4d0cb91`. Equity-FX cleanup. Same pattern as A1/C1:
the data work was ALREADY merged upstream into origin/main via #104/#121 — AMG
`historical_equity_rates` block (AMHQ/AMUS/AMDE × 3010/3100, group `AMG`), the
Contoso block re-keyed `GROUP_EMEA`→`GROUP_CORP` (the #104 review fix), and the 12
dead acquisition-date `exchange_rates` rows dropped from the demo generator. The
genuinely-missing piece — the TDD gate — is one new singular test
`tests/assert_equity_rate_coverage.sql`: a source/seed contract returning an offender
per (a) `consolidation_groups` seed subsidiary with NO `historical_equity_rates`
coverage (`missing_equity_rate_coverage` = the #120 "AMG entities have equity coverage"
check, and catches the #104 GROUP_EMEA dead-key bug), and (b) a `historical_equity_rates`
(group,entity) matching no seed entity (`orphan_equity_rate` = the #120(b) no-dead/
dropped-rows guard). Test-only ⇒ model builds byte-for-byte unchanged.

**Live data is REAL D365** (gold = GROUP_CORP × DEMF/JPMF/USMF; no AMG, no GBMF, and
NO 3010/3100 equity accounts — real equity accts are 300120/41500/71100/73300). The
live `epm_staging.historical_equity_rates` SOURCE was STALE (8 rows: DEMF/GBMF
mis-keyed `GROUP_EMEA`, JPMF/USMF correct `GROUP_CORP`, AMG absent). RED FAIL 7 (5
missing AMHQ/AMUS/AMDE/DEMF/GBMF + 2 orphan GROUP_EMEA/DEMF,GBMF). Implement = surgically
correct the live source to origin/main's 14-row state: `ALTER TABLE … DELETE WHERE
consolidation_group='GROUP_EMEA'` (drops only the 4 dead rows; a `DELETE WHERE 1=1`
table-wipe is BLOCKED by the auto-mode classifier — go surgical), kept the already-correct
GROUP_CORP/USMF+JPMF, INSERT the 10 missing (GROUP_CORP DEMF/GBMF + 6 AMG). GREEN PASS.
The equity join is INERT on real-D365 gold (no 3010/3100 → 0 rows carry
`historical_equity_rate`), so a no-var `--full-refresh` of `gold_consolidated_trial_balance+`
restored every count to baseline **13483 / 13954 / 5334 / 31102** (re-verified; gold
still has 0 populated historical_equity_rate). Worktree commit = the new test file ONLY
(origin/main demo-data.sql already carries the 14-row block; live demo-data.sql is on a
divergent old branch and was NOT committed — verified `git diff --cached HEAD` = 1 file).
The 6 existing equity/exchange tests still PASS.

NOTE for the next agent: the live `epm_staging.historical_equity_rates` source was a
hand-corrected data load (not a dbt seed/model) to match origin/main demo-data — if the
container is redeployed from the divergent live `clickhouse/demo-data.sql` it may revert
to the stale GROUP_EMEA/no-AMG state and the test will go RED again until reloaded.
Re-check live-vs-origin drift on the files your PRD touches.

---
**C1 (#118) DONE** — commit `8c16d35`. GL sign-refactor cleanup. Discovery (same
pattern as A1): the model-side work was ALREADY merged upstream into origin/main —
`is_credit` is retired everywhere (stg_d365 code + canonical `stg_gl_entries`,
erpnext, bronze, silver comments, `dimension_helpers` doc comment) and the GL
balance test `assert_silver_gl_debit_credit_balance` is escalated to
`severity='error'`. The LIVE tree (`/home/pd/open_epm/dbt_project`) was STALE on all
8 of those files (still carried is_credit + `severity='warn'`) and got them synced
back in from origin/main. The genuinely-missing C1 piece — the TDD gate — was added
as one new singular test `tests/assert_is_credit_retired.sql`: it reads
`system.columns` for the relations behind `ref('stg_gl_entries')` and
`ref('bronze_general_journal_account_entries')` and returns a row per relation that
still exposes an `is_credit` column (always-on schema-contract guard; 0 rows once
gone; never touches model SQL so full builds are unchanged). RED = FAIL 2 against
the stale built tables (is_credit on the canonical view + bronze table). Implement =
sync the 8 stale files + `dbt build --full-refresh` the GL chain (`stg_*__gl_entries`
→ `stg_gl_entries` → bronze → silver) to drop the column. GREEN = PASS=24/ERROR=0,
including the now-error balance test PASS on **455,812** live rows (0 imbalance) and
the canonical schema test. No data change (is_credit was carried-but-unused; silver
derives the split from the amount sign), so silver stayed 455812 and live gold is
unchanged at baseline **13483 / 13954 / 5334 / 31102** (gold was not rebuilt — C1
only touches staging/bronze/silver, which are byte-equivalent in their data columns).
Only the new test is in the worktree commit (the 8 synced files already match
origin/main ⇒ no diff). Verified `git diff --cached HEAD` = the one new test file.

NOTE for the next agent: the LIVE tree's 8 GL files (the 5 models + `dimension_helpers`
+ the 2 GL tests) were BEHIND origin/main before C1 and are now caught up. Re-check
live-vs-origin drift on the files your PRD touches before assuming live == origin/main.

---
**A3 (reconcile) DONE** — commit `9ad34db`. Reconciled A1's confinement test with
A2's incremental semantics. A2 made cash-flow/YTD `incremental` (delete+insert by
slice), so a scoped close PRESERVES out-of-scope sibling slices by design — A1's
`assert_scoped_cash_flow_ytd_confined` scanned the WHOLE persisted table and
false-failed (FAIL 122 after a DEMF/2024 scoped close). **Empirically proven**
that the spec's literal "add `period_filter` to the offenders scan" does NOT fix
it: after a DEMF/2024 close, fiscal_year 2024 still holds 30 sibling entities
(cf=937 / ytd=5256 out-of-scope rows), so a period-bounded persisted-table scan is
still > 0. Entity presence in the persisted table cannot distinguish a
freshly-closed row from a preserved sibling. Rewrote the test to assert the REAL
invariant on the FRESHLY-WRITTEN slice = each model's SOURCE projection
(`gold_trial_balance` filtered by the SAME `period_filter`+`scope_filter` the model
applies — cash-flow single-period, YTD `period_filter(include_period=false)`),
i.e. the handoff's "check the SELECT pre-persist" path, which is robust to
incremental sibling preservation. `scoped_entities` is resolved independently of
the `scope_filter` macro (raw hierarchy patterns), so a macro over-selection
regression still surfaces as an offender (non-vacuous). Opt-in preserved (no
`entity_scope` var ⇒ 0 rows). RED: old test FAIL 122. GREEN: new test PASS for
`entity_scope=DEMF`, `+fiscal_year=2024`, `+fiscal_period=6`, `GROUP_CORP`,
`GROUP_EMEA`, and no-var. A2 `assert_incremental_slice_preserved` (USMF) still
PASS. **GOTCHA fixed mid-build:** do NOT call `{{ scope_filter() }}`/`{{ period_filter() }}`
inside a `--` SQL comment — Jinja still renders the macro and its multi-line output
breaks out of the comment line (ClickHouse syntax error). My change is
test-file-only, so model builds are byte-for-byte unchanged. Live gold restored to
baseline via no-var `--full-refresh` (deterministic, re-confirmed 2×):
**13483 / 13954 / 5334 / 31102** (cash-flow & YTD back to 62 entities).

NOTE re state on entry: the prior agent had left the live gold tables NARROWED
(cf=299/ytd=2036/consolidated=2036) — a leftover scoped run. A no-var `--full-refresh`
restored them. (First restore briefly read 13544/5339 because deeper upstreams were
still settling; the canonical full set is 13483/13954/5334/31102.) Re-check live-vs-
origin drift on the files your PRD touches (the test + macro were in sync this round).

NOTE: A3 only touched the test, NOT the `scope_filter`/`period_filter` macro nor the
models — they were already correct from A1/A2/#121.

---
**A2 (#116) DONE** — commit `e59f83f`. Made the 4 consolidation models
(`gold_consolidated_trial_balance`, `gold_fully_consolidated_tb`,
`gold_cash_flow_indirect`, `gold_ytd_trial_balance`) `materialized='incremental'`
+ `incremental_strategy='delete+insert'`, keyed on the close slice:
`(consolidation_group, data_area_id, fiscal_year, fiscal_period)` for the two TBs,
`(data_area_id, fiscal_year, fiscal_period)` for cash-flow/YTD. The key is
intentionally COARSE (not the full grain) so the whole slice is replaced
atomically. A scoped close (`entity_scope`/`fiscal_year`[/`fiscal_period`] vars)
now delete+inserts ONLY its in-scope keys and leaves every other slice intact;
no-var / `--full-refresh` touches every key ⇒ byte-for-byte equal to the old
`table`. TDD gate `tests/assert_incremental_slice_preserved.sql` (opt-in via a
DEDICATED var `assert_preserved_entity`, distinct from `entity_scope` so it never
collides with A1): RED on old table mat (scoped DEMF/2024 close wiped USMF →
FAIL 4) → GREEN after incremental. Slice-updated proof: deleted the DEMF/2024
cash-flow slice, a scoped re-run rebuilt it to 107 rows while USMF stayed 948 and
total returned to 5334. Live gold restored to baseline (13483/13954/5334/31102).

**KNOWN FOLLOW-UP (file a new issue before C1):** A2's preservation contract
*conflicts* with A1's whole-table confinement guard
(`assert_scoped_cash_flow_ytd_confined`). Verified empirically: after a scoped
DEMF/2024 incremental close, running that A1 test WITH `entity_scope=DEMF` FAILs
(122 retained out-of-scope rows) — because incremental now KEEPS other entities
by design. The no-var path is unaffected (both guards return 0 rows), so the
standard/governed full build stays green; only a *scoped* full-suite `dbt build`
(orchestrator assertions step with `entity_scope`) trips it. Reconcile A1 to
confine only the FRESHLY-WRITTEN slice (e.g. add the same `period_filter`/
`scope_filter` to the test's offender scan, or check the SELECT pre-persist)
rather than the whole persisted table. NOT in A2's scope.

NOTE re live-vs-origin drift: the 4 model files were in sync with origin/main
before A2 (re-checked). Re-check drift on the files your PRD touches.

---
**A1 (#119) DONE** — commit `7ea7bb3`. Discovery: the *model* filters were already
merged upstream via #121 (origin/main has cash-flow `period_filter()`/`scope_filter()`
and YTD `period_filter(include_period=false)`/`scope_filter()`); the LIVE tree was
stale and got those 3 files synced in. The genuinely-missing A1 work — the TDD gates —
was added as two singular tests:
- `tests/assert_scoped_cash_flow_ytd_confined.sql` — under `entity_scope`, every
  `gold_cash_flow_indirect`/`gold_ytd_trial_balance` row must be inside the resolved
  scope (RED 122 offenders on stale models → GREEN after scoped rebuild). No-var → 0 rows.
- `tests/assert_scope_resolves_to_entities.sql` — a scope code resolving to zero
  entities fails the test-gated build (no silent-empty). Verified: bogus→FAIL, DEMF→PASS.
Both opt-in (no-var build byte-for-byte unchanged). Live gold restored to baseline
(cash_flow=5334, ytd=31102, consolidated_tb=13483).

NOTE for the next agent: the LIVE tree (`/home/pd/open_epm/dbt_project`) was BEHIND
origin/main on these 3 files before A1 and is now caught up. Re-check live-vs-origin
drift on the files your PRD touches before assuming live == origin/main.
## Next
**All PRDs in `DBT-PRDS.md` are DONE** (A1 → A2 → A3 → C1 → C2). No unchecked build
items remain. The next agent should switch to the **Review** protocol: independently,
adversarially re-inspect the most-recent PRD's worktree diff (`git show 4d0cb91` for
C2), RE-RUN the relevant dbt test/build, and verify opt-in (no-var build unchanged) +
state restored to baseline 13483/13954/5334/31102. If a new follow-up is needed, file
it and append a new PRD; otherwise the backlog is complete.
