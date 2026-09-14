{#
    konsolidat#191: cast_to_decimal128(expr, scale) must recover the exact
    decimal value that was submitted, not truncate it.

    toDecimal128(Float64, scale) truncates toward zero on the binary double,
    which is usually a hair below the decimal the value was entered as (e.g.
    0.29 becomes 0.28). Summed over a trial-balance batch, balanced raw
    batches arrive unbalanced in bronze (konsolidat#191).

    Cases: an ordinary two-decimal amount, a large amount from the reported
    batch (177,485,814.95), a negative amount, and a Nullable(Float64) input
    (assumeNotNull must still work through toString).

    Reads no model or source, so it cannot skip anything; it runs wherever
    `dbt test` / `dbt build` runs.
#}

with cases as (
    select * from values(
        'label String, got Decimal128(2), expected Decimal128(2)',
        ('ordinary two-decimal amount', {{ cast_to_decimal128('toFloat64(0.29)', 2) }}, toDecimal128('0.29', 2)),
        ('large batch total (konsolidat#191)', {{ cast_to_decimal128('toFloat64(177485814.95)', 2) }}, toDecimal128('177485814.95', 2)),
        ('negative amount', {{ cast_to_decimal128('toFloat64(-1234.56)', 2) }}, toDecimal128('-1234.56', 2)),
        ('nullable float input', {{ cast_to_decimal128('toNullable(toFloat64(5.1))', 2) }}, toDecimal128('5.1', 2))
    )
)

select *
from cases
where got != expected
