# Report Catalog

Quick reference for all 22 gold models with sample `=EPM()` formulas for common reports.

## Model Quick Reference

### Financial Statements

| Model | Purpose | Key Measures |
|-------|---------|-------------|
| `gold_trial_balance` | Period-level trial balance | `period_debit`, `period_credit`, `period_net_amount`, `transaction_count` |
| `gold_pnl_by_period` | Income statement (revenue + expense only) | `period_net_amount` |
| `gold_balance_sheet` | Balance sheet (asset + liability + equity) | `cumulative_balance` |
| `gold_bs_movement` | BS movement schedule | `opening_balance`, `period_movement`, `closing_balance` |

### Time Aggregations

| Model | Purpose | Key Measures |
|-------|---------|-------------|
| `gold_ytd_trial_balance` | Year-to-date running totals | `ytd_debit`, `ytd_credit`, `ytd_net_amount` |
| `gold_pnl_quarterly` | Quarterly P&L | `quarter_net_amount` |
| `gold_pnl_half_yearly` | Half-yearly P&L | `half_net_amount` |
| `gold_period_hierarchy` | Period → quarter/half mapping | `fiscal_quarter`, `fiscal_half` |

### Budgeting & Variance

| Model | Purpose | Key Measures |
|-------|---------|-------------|
| `gold_spread_budget` | Monthly budget (spread from annual) | `period_amount`, `annual_amount` |
| `gold_variance_analysis` | Actual vs budget | `variance_abs`, `variance_pct`, `variance_favorable` |
| `gold_variance_ytd` | YTD variance | `ytd_actual`, `ytd_budget` |
| `gold_variance_quarterly` | Quarterly variance | — |
| `gold_prior_year_comparison` | Year-over-year | `current_amount`, `prior_year_amount`, `yoy_variance_abs` |

### Consolidation

| Model | Purpose | Key Measures |
|-------|---------|-------------|
| `gold_consolidated_trial_balance` | FX-translated entity TB | `translated_amount`, `group_amount`, `nci_amount` |
| `gold_ic_eliminations` | Intercompany entries | `elimination_amount` |
| `gold_fx_revaluation` | CTA entries | `cta_amount` |
| `gold_consolidation_adjustments` | Top-side journals | `net_amount` |
| `gold_fully_consolidated_tb` | 4-layer consolidated TB | `amount` by `adjustment_type` |
| `gold_consolidated_ytd` | YTD consolidated | `ytd_amount` |

### Allocation & Scenarios

| Model | Purpose | Key Measures |
|-------|---------|-------------|
| `gold_allocation_results` | Cost allocation outputs | `pool_amount`, `driver_weight`, `allocated_amount` |
| `gold_scenario_trial_balance` | Cross-scenario union | `amount` by `scenario_id` |
| `gold_scenario_versions` | Scenario metadata | `is_active` |

## Sample Reports

### P&L by Month

A 12-month income statement for one entity.

```
=EPM($B$1, $D$1, B$2, $A3)
```

Where B1=entity, D1=year, row 2=period numbers (1–12), column A=account codes.

| | A | B | C | ... | M |
|---|---|---|---|---|---|
| 1 | Entity: | USMF | Year: | ... | 2024 |
| 2 | Account | 1 | 2 | ... | 12 |
| 3 | 4100 - Revenue | `=EPM($B$1,$D$1,B$2,$A3)` | ... | ... | ... |
| 4 | 5100 - COGS | `=EPM($B$1,$D$1,B$2,$A4)` | ... | ... | ... |
| 5 | **Gross Profit** | `=B3+B4` | | | |
| 6 | 6100 - SGA | `=EPM($B$1,$D$1,B$2,$A6)` | ... | ... | ... |

### Quarterly P&L

```
=EPM("USMF", 2024, "Q1", "4100")
=EPM("USMF", 2024, "Q2", "4100")
=EPM("USMF", 2024, "Q3", "4100")
=EPM("USMF", 2024, "Q4", "4100")
```

### Budget vs Actual (Full Year)

| | A | B | C | D | E |
|---|---|---|---|---|---|
| 2 | Account | Actual FY | Budget FY | Variance | Fav? |
| 3 | 4100 | `=EPM("USMF",2025,"FY","4100")` | `=EPM_BUDGET("USMF",2025,"FY","4100")` | `=EPM_VARIANCE("USMF",2025,"FY","4100")` | `=EPM("USMF",2025,"FY","4100","variance_favorable","variance")` |

### Multi-Entity Comparison

| | A | B | C | D | E |
|---|---|---|---|---|---|
| 2 | Account | USMF | DEMF | GBMF | JPMF |
| 3 | 4100 | `=EPM("USMF",2024,"FY",$A3)` | `=EPM("DEMF",2024,"FY",$A3)` | `=EPM("GBMF",2024,"FY",$A3)` | `=EPM("JPMF",2024,"FY",$A3)` |

### Debit/Credit Detail

For accounts where you need both sides:

```
=EPM_DEBIT("USMF", 2024, 5, "1300")    ' Receivables debit
=EPM_CREDIT("USMF", 2024, 5, "1300")   ' Receivables credit
```

### Cost Center Drill-Down

```
=EPM("USMF", 2024, "FY", "7100", "period_net_amount", "actuals", "IT")
=EPM("USMF", 2024, "FY", "7100", "period_net_amount", "actuals", "SALES")
=EPM("USMF", 2024, "FY", "7100", "period_net_amount", "actuals", "FACILITY")
```

### YTD Tracking

```
=EPM("USMF", 2024, 5, "4100", "ytd_net_amount")
```

Returns the cumulative net amount from period 1 through period 5.

## Tips

- Use **absolute references** (`$B$1`) for entity/year parameters and relative references for the varying dimension
- **Period ranges** (`Q1`, `H1`, `FY`) save cells and improve readability
- **EPM_BUDGET** and **EPM_VARIANCE** are shortcuts — the full `EPM()` with measure/scenario parameters gives access to all measures
- **Ctrl+Shift+R** refreshes the active sheet; all EPM cells batch into a single API call
- For large workbooks (1000+ EPM cells), use **EPM_RefreshAll** to process all sheets sequentially

## Next Steps

- [Excel VBA Guide](excel-vba-guide.md) — Full formula and macro reference
- [Gold Models](../data-dictionary/gold-models.md) — Complete column documentation
- [Variance Analysis Guide](variance-analysis-guide.md) — Favorable/unfavorable logic
