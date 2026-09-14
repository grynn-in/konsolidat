-- depends_on: {{ ref('bronze_trial_balance_submissions') }}

{#
    konsolidat#191: cast_to_decimal128(expr, scale) must recover the exact
    decimal value that was submitted, not truncate it.

    toDecimal128(Float64, scale) truncates toward zero on the binary double,
    which is usually a hair below the decimal the value was entered as (e.g.
    0.29 becomes 0.28). Summed over a trial-balance batch, balanced raw
    batches arrive unbalanced in bronze (konsolidat#191). A float *sum* (e.g.
    two submitted amounts added together, as gold_scenario_trial_balance.sql
    does) has the same problem even after the text-route fix, because the
    shortest text form of the sum itself can sit a hair below the cent
    (0.7 + 0.1 = 0.7999999999999999) — the macro now rounds to the target
    scale before the text step so this casts exactly too.

    Cases: an ordinary two-decimal amount, a large amount from the reported
    batch (177,485,814.95), a negative amount, a Nullable(Float64) input
    (assumeNotNull must still work through toString), a float sum whose
    binary result is a hair short of the cent, and a very small value at
    scale 12 (the exchange-rate caller's scale).

    Depends on bronze_trial_balance_submissions (not read otherwise) purely
    so CI's indirect test selection picks this test up whenever that model
    is selected — see dbt_project/tests/assert_ic_difference_account_in_chart.sql
    for the same pattern. bronze_trial_balance_submissions feeds
    silver_gl_entries -> gold_trial_balance_by_partner ->
    gold_consolidated_trial_balance, which is in tb_only_first_build.py's
    MUST_CREATE, so `dbt build --select @silver_main_accounts` (the
    tb-only-first-build CI job) now selects this test too.
#}

with cases as (
    select * from values(
        'label String, got Decimal128(12), expected Decimal128(12)',
        ('ordinary two-decimal amount', {{ cast_to_decimal128('toFloat64(0.29)', 12) }}, toDecimal128('0.29', 12)),
        ('large batch total (konsolidat#191)', {{ cast_to_decimal128('toFloat64(177485814.95)', 12) }}, toDecimal128('177485814.95', 12)),
        ('negative amount', {{ cast_to_decimal128('toFloat64(-1234.56)', 12) }}, toDecimal128('-1234.56', 12)),
        ('nullable float input', {{ cast_to_decimal128('toNullable(toFloat64(5.1))', 12) }}, toDecimal128('5.1', 12)),
        ('float sum a hair short of the cent', {{ cast_to_decimal128('toFloat64(0.7) + toFloat64(0.1)', 2) }}, toDecimal128('0.80', 2)),
        ('scale-12 small value (exchange-rate caller)', {{ cast_to_decimal128('toFloat64(0.0000001)', 12) }}, toDecimal128('0.0000001', 12))
    )
)

select *
from cases
where got != expected
