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
None done yet.
## Next
A1 (#119) — extend scope/period coverage to cash-flow + YTD.
