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
C1 (#118) — GL sign refactor cleanup: retire dead `is_credit`, fix stale
comments, escalate the GL balance singular test (warn → error).
