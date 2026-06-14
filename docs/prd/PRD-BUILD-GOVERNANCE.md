# PRD: Pipeline Build Governance

**Status:** Implemented (konsol #16)
**Date:** 2026-06-11
**Repos:** `konsolidat` (dbt tags), `konsol` (Frappe governance layer)

## Problem

Saving any of 9 Frappe doctypes fires a **full `dbt build`** with no guard:

- `epm_raw` may be empty → full build wipes gold tables (600K+ rows)
- No approval for high-risk rebuilds (actuals, consolidation)
- No audit trail of what triggered builds or their outcomes
- No selective builds — always rebuilds everything

## Solution

Replace fire-and-forget `dbt build` with a **governed, tag-aware, approval-gated** system.

## Scope

### 1. dbt Domain Tags (`konsolidat`)

| Tag | Models | Needs epm_raw? |
|---|---|---|
| `staging` | 5 gold models (hierarchy, scenarios, adjustments, budget spread) | NO |
| `actuals` | bronze + silver + GL gold models (trial balance, P&L, BS, FX) | YES |
| `scenarios` | variance analysis, scenario TB | YES |
| `consolidation` | IC elim, NCI, equity method, waterfall, allocation | YES (transitive) |

### 2. Pipeline Build Request (konsol)

New doctype `PBR-.#####` with:
- **Scope** → risk auto-classification (staging=low, others=high)
- **Workflow**: Draft → Pending Review → Approved → Running → Completed/Failed
- Low risk: auto-approve. High risk: EPM Admin approval required.
- Preflight: blocks if Airbyte sync failed/running/never-ran (for raw-dependent scopes)
- Captures build output, timing, errors

### 3. Airbyte Sync Status (konsol)

- Webhook endpoint `airbyte_sync_complete()` updates EPM Settings
- Sync info displayed on PBR form for admin decision-making
- Preflight check references sync status before approving raw-dependent builds

### 4. EPM Roles

- **EPM User**: save docs, read-only on build requests
- **EPM Analyst**: create manual build requests
- **EPM Admin**: approve high-risk builds

### 5. Refactored Hook Flow

Doc saves → create PBR (scope=staging, low risk) → auto-approve → selective `dbt build --select tag:staging`

## Acceptance Criteria

1. `dbt ls --select tag:staging` returns exactly 5 gold models
2. Saving a Consolidation Group creates a PBR with scope=staging, auto-approved
3. Manual PBR with scope=actuals goes to Pending Review
4. Preflight blocks when `last_airbyte_sync_status=Failed`
5. Approved PBR runs `dbt build --select tag:<scope>` (not full build)
6. Build output, timing, and errors captured on PBR doc
7. All 9 trigger doctypes mapped in `DOCTYPE_BUILD_MAP`
8. All structural tests in `test_build_governance.py` pass
