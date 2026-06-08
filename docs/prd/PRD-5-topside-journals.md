# PRD-5: Top-Side Journal Adjustments

## Problem
Consolidation requires manual adjustment entries that don't exist in any subsidiary's GL:
- Goodwill amortization
- Fair value adjustments
- Reclassifications
- Audit adjustments
- Opening balance adjustments

Currently there is no way to post entries at the consolidated level.

## Requirements

### R1: Staging table for consolidation adjustments
New ClickHouse table `epm_staging.consolidation_adjustments`:
```sql
consolidation_group String,
adjustment_type String,          -- 'topside', 'reclassification', 'audit', 'opening'
journal_id String,               -- unique per adjustment entry
data_area_id String DEFAULT '',  -- empty = group-level
fiscal_year UInt16,
fiscal_period UInt8,
main_account String,
debit_amount Decimal(18,2) DEFAULT 0,
credit_amount Decimal(18,2) DEFAULT 0,
description String,
posted_by String,
posted_at DateTime DEFAULT now()
```

### R2: API endpoints
- `POST /api/v1/consolidation-adjustments` — post adjustment journal (batch of lines)
- `GET /api/v1/consolidation-adjustments/{consolidation_group}` — list adjustments
- `DELETE /api/v1/consolidation-adjustments/{journal_id}` — reverse/delete an adjustment

### R3: dbt model `gold_consolidation_adjustments`
- Reads from staging table
- Validates: each journal_id must have debits = credits (balanced entry)
- Outputs in same grain as consolidated TB

### R4: Integration with consolidated TB
- `gold_consolidated_trial_balance` unions:
  1. Translated entity balances (existing)
  2. IC eliminations (existing model, folded in)
  3. **Top-side adjustments** (new)
  4. **CTA entries** (from PRD-2)
- Or: create a new `gold_fully_consolidated_tb` that unions all four

### R5: Adjustment type tracking
- Every row in final consolidated output has `adjustment_type`:
  - `'entity'` — normal translated balance
  - `'ic_elimination'` — from IC rules
  - `'topside'` — manual adjustment
  - `'cta'` — currency translation adjustment

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_topside_journal_balanced` | Per journal_id: sum(debit_amount) = sum(credit_amount) within 0.01 |
| `assert_adjustments_in_consolidated` | Posted adjustments appear in gold_fully_consolidated_tb |
| `assert_adjustment_type_populated` | Every row in gold_fully_consolidated_tb has a non-empty adjustment_type |
| `assert_consolidated_tb_still_balances` | After including top-side entries, debits still = credits per group/period |

## Out of Scope
- Approval workflow (post = immediate)
- Recurring journal templates
