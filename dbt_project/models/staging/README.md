# Staging: the ERP adapter contract

Every ERP enters the warehouse through one adapter folder,
`models/staging/<erp>/`. The canonical models in `canonical/` UNION the
adapters listed in the `erp_sources` var, and bronze reads only the canonical
models. The contract below is stated once, here. Every adapter model links
back to it from its header.

## Sign convention

**Amounts are signed at the boundary, split once in silver, and never inferred
again.**

1. **The adapter delivers `amount` SIGNED** in the accounting (entity)
   currency. Debit is positive, credit is negative, one row per posting line.
   A source that stores magnitudes plus a debit/credit flag (or separate debit
   and credit columns) resolves the sign in the adapter and nowhere later.
   ERPNext's `amount = debit - credit` is an example. `transaction_currency_amount`
   follows the same sign.
2. **Silver splits it once.** `silver_gl_entries` derives `debit_amount` and
   `credit_amount` from the sign of the amount (konsolidat#112). It never uses a
   flag: D365's `IsCredit` can disagree with the sign on storno lines
   (#118, `assert_is_credit_retired`). Submitted trial balances enter silver
   with explicit debit and credit columns, so they need no derivation.
3. **Nothing downstream re-derives a sign.** `period_net_amount` in
   `gold_trial_balance` is `sum(debit_amount) - sum(credit_amount)`, signed
   (`assert_period_net_equals_debit_minus_credit`). Gold models read the signed
   movement. They don't take `abs()`, and they don't reapply a sign from an
   account type.

If a feed breaks rule 1, it books every credit as a debit and every trial
balance goes one-sided. The retired demo generator did exactly that
(konsolidat#155).

## Canonical models and the columns each adapter must emit

An adapter model is named `stg_<erp>__<entity>` and must emit at least these
columns. The canonical model selects them by name, so an adapter may carry
extra ERP-specific columns. Bronze joins those from the adapter directly
(for example D365's `reporting_currency_amount`).

| Canonical model | Adapter columns |
|---|---|
| `stg_gl_entries` | `erp_source, record_id, entity_id, posting_date, fiscal_year, fiscal_period, main_account, account_name, amount, transaction_currency_amount, transaction_currency, description, journal_number, posting_type, ledger_account, dim_cost_center, dim_department, dim_business_unit, _loaded_at, _raw_id` |
| `stg_trial_balance` | `erp_source, entity_id, main_account, account_name, fiscal_year, opening_balance, debit_amount, credit_amount, closing_balance, currency_code, account_type, _loaded_at, _raw_id` |
| `stg_budget_entries` | `erp_source, record_id, entity_id, posting_date, main_account, amount, transaction_amount, transaction_currency, budget_model, budget_status, dim_cost_center, dim_department, _loaded_at, _raw_id` |
| `stg_accounts` | `erp_source, account_id, account_name, account_type, account_category, debit_credit_default, chart_of_accounts, is_suspended, _loaded_at, _raw_id` |
| `stg_legal_entities` | `erp_source, entity_id, entity_name, accounting_currency, reporting_currency, party_number, country_region, _loaded_at, _raw_id` |
| `stg_exchange_rates` | `erp_source, from_currency, to_currency, valid_from, valid_to, exchange_rate, rate_type, _loaded_at, _raw_id` |
| `stg_fiscal_periods` | `erp_source, calendar_id, calendar_name, fiscal_year, start_date, end_date, _loaded_at, _raw_id` |

Column rules:

- `erp_source` is a literal: the folder name. It must be one of the values
  accepted in `canonical/_canonical__models.yml` and
  `tests/staging/test_erp_source_valid.sql`.
- `record_id` is numeric, stable across runs, and fits in Int64. Bronze casts
  it with `toInt64`, and `bronze_general_journal_account_entries` uses it as
  its delete+insert key. A string key is hashed, as ERPNext's `name` is.
- `entity_id` is the legal-entity code, the same value in every model of one
  adapter; use the ERP's canonical (upper-case) code. `stg_gl_entries` drops GL lines with an empty
  `entity_id` (#105).
- `posting_date` is a `YYYY-MM-DD` string.
- GL `amount` is not NULL and signed as above. `sum()` skips a NULL, which
  would let an unbalanced journal pass.
- GL `amount` and `transaction_currency_amount` must UNION with D365's
  `Nullable(Decimal(38, 9))`. ClickHouse refuses `Decimal UNION Float64`
  (`NO_COMMON_TYPE`), so an adapter whose raw amounts are Float64 casts them
  (`toDecimal128(x, 9)`). The failure breaks `stg_gl_entries`, and with it
  every model downstream, for every source.
- `journal_number` identifies a posting unit whose lines net to zero within
  one entity: a voucher (ERPNext `voucher_no`) or a journal of balanced
  vouchers (D365 `JournalNumber`).
- Trial balance: `debit_amount` and `credit_amount` are non-negative period
  totals. `opening_balance` and `closing_balance` are signed, debit positive,
  with `closing = opening + debit - credit` (`silver_trial_balance.calculated_closing`).
- Budget `amount`: **no sign convention is defined or enforced yet.** Budgets
  arrive as magnitudes (the D365 feed on the test stack is all positive,
  revenue accounts included) and no layer signs them, while actuals are signed.
  Defining the rule end to end is #174.
- Dimension values are emitted raw. `stg_gl_entries` and `stg_budget_entries`
  harmonize them centrally through the `dimension_mappings` crosswalk.

## Enablement

`d365_fo` is mandatory, because bronze refs several `stg_d365_fo__*` models
directly. Every other ERP is optional. Each of its models starts with a
`config(enabled = '<erp>' in var('erp_sources', ['d365_fo']))` line, and it
must live in the model, not in `dbt_project.yml` (see any `erpnext/` model
for why). The canonical models UNION the same var, so enablement and the
union can't drift apart.

## Checks

| Check | What it enforces |
|---|---|
| `tests/staging/test_canonical_gl_journals_balance.sql` | Every source: each (erp_source, entity_id, journal_number) nets to zero. |
| `tests/assert_d365_gl_vouchers_balance.sql` | D365, at a finer grain: each voucher nets to zero, entity-less headers included. |
| `not_null` on `stg_gl_entries.amount` | No NULL amount slips past the balance tests. |
| `tests/staging/test_canonical_gl_entries_schema.sql` | Key GL columns exist, so a missing one fails compilation (it doesn't list every column). |
| `tests/staging/test_canonical_gl_entries_not_null.sql` | Key GL columns are populated. |
| `tests/staging/test_erp_source_valid.sql` | `erp_source` is a known value. |
| `tests/assert_silver_gl_debit_credit_balance.sql` | Silver debits equal credits per entity and year. |

## Adding an ERP

1. Add `models/staging/<erp>/` with a `stg_<erp>__<entity>` model for each
   canonical model above, each carrying the enablement line and a header link
   to this file.
2. Add a `_<erp>__sources.yml` and a `_<erp>__models.yml`.
3. Add `<erp>` to the accepted `erp_source` values (see Column rules) and a
   tag block under `models: open_epm: staging:` in `dbt_project.yml`.
4. Resolve the sign in the adapter (rule 1), then build with `<erp>` in
   `erp_sources`. `test_canonical_gl_journals_balance` fails, naming the journal,
   if a credit arrived unsigned.

## Known gaps

- Budget sign: not defined for any source (see the Budget rule above, #174).
- `stg_erpnext__trial_balance` hard-codes `toFloat64(0) as opening_balance`,
  so enabling `erpnext` fails `stg_trial_balance` with `NO_COMMON_TYPE`
  against D365's `Decimal(38, 9)`, whatever type the feed lands as (#173).
- `stg_erpnext__gl_entries` doesn't cast `amount`. If the ERPNext feed lands
  `debit`/`credit` as Float64, enabling `erpnext` fails `stg_gl_entries` with
  `NO_COMMON_TYPE` (see Column rules, #173).
