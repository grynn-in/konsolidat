# PRD-4: Minority Interest (Non-Controlling Interest)

## Problem
When ownership < 100%, the consolidated TB applies ownership % uniformly. Under IFRS 10 / ASC 810, you must show:
- **Group share**: ownership_pct × translated_amount
- **Minority interest (NCI)**: (1 - ownership_pct) × translated_amount

NCI must appear as a separate line in equity on the balance sheet and as a separate split in the income statement.

## Requirements

### R1: NCI columns on consolidated TB
Add to `gold_consolidated_trial_balance`:
- `nci_pct` = 1 - ownership_pct
- `nci_amount` = translated_amount × nci_pct
- Rename existing `group_amount` semantics: `group_amount` = translated_amount × ownership_pct (already correct)
- `total_amount` = group_amount + nci_amount (= translated_amount, for verification)

### R2: NCI summary model
New model `gold_minority_interest`:
- Aggregates NCI amounts per consolidation_group, data_area_id, fiscal_year, fiscal_period
- Splits into: NCI in P&L (income attributable to NCI) and NCI in equity (balance sheet NCI)
- Only populated for entities where ownership_pct < 1.0

### R3: NCI flows into reporting
- Cube schema for consolidated TB exposes `nci_amount` as a measure
- P&L report view shows "Net income attributable to NCI" line
- Balance sheet view shows "Non-controlling interest" in equity

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_nci_zero_for_full_ownership` | Where ownership_pct = 1.0, nci_amount = 0 |
| `assert_nci_plus_group_equals_translated` | group_amount + nci_amount = translated_amount within 0.01 |
| `assert_nci_exists_for_partial_ownership` | Entities with ownership_pct < 1.0 have nci_amount ≠ 0 (when local_amount ≠ 0) |
| `assert_nci_pnl_split` | NCI P&L amount = sum(is_pnl rows × nci_pct) |

## Out of Scope
- NCI in business combination (acquisition accounting / goodwill allocation)
- Changes in ownership without loss of control
