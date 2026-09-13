{#
    The shared FX magnitude cases (konsolidat#176 / konsol #174). The SAME case
    table runs through konsol's konsol.group_rates.magnitude_problem, so the two
    implementations of the rule cannot drift. Keep the VALUES below aligned
    with konsol's list, case for case.

    Rule (macros/fx_magnitude.sql): a currency has no reference when
    isNaN(usd_log10) OR (usd_log10 = 0 AND currency_code != 'USD'); a rate is
    plausible when abs(log10(rate) - (usd_log10(to) - usd_log10(from))) <= 1.

    expected: ok | implausible | no_reference | invalid.
    Reads no model or source, so it cannot skip anything; it runs wherever
    `dbt test` / `dbt build` runs (CI only parses the project).
#}

with cases as (
    select * from values(
        'from_ccy String, to_ccy String, rate Float64, from_log10 Float64, to_log10 Float64, expected String',
        ('JPY', 'USD', 0.006607,  2.17, 0.0,  'ok'),            -- true JPY
        ('JPY', 'USD', 0.6607,    2.17, 0.0,  'implausible'),   -- JPY x100
        ('USD', 'JPY', 151.35,    0.0,  2.17, 'ok'),            -- the other direction
        ('IDR', 'USD', 0.0000617, 4.21, 0.0,  'ok'),            -- true IDR (the old [1e-4, 1e4] band refused it)
        ('IDR', 'USD', 0.00617,   4.21, 0.0,  'implausible'),   -- IDR x100
        ('USD', 'USD', 1.0,       0.0,  0.0,  'ok'),            -- USD into itself
        ('XNR', 'USD', 0.5,       nan,  0.0,  'no_reference'),  -- a NaN reference
        ('XZR', 'USD', 0.5,       0.0,  0.0,  'no_reference'),  -- 0 for a non-USD currency = unset
        ('XPG', 'USD', 0.001,     3.0,  0.0,  'ok'),            -- a currency pegged at 0.001
        ('JPY', 'USD', 0.0,       2.17, 0.0,  'invalid'),       -- zero
        ('JPY', 'USD', nan,       2.17, 0.0,  'invalid')        -- not a finite number
    )
),

ref_mag as (
    select currency_code, usd_log10
    from (
        select from_ccy as currency_code, from_log10 as usd_log10 from cases
        union distinct
        select to_ccy, to_log10 from cases
    )
    where {{ fx_has_reference('currency_code', 'usd_log10') }}
),

checked as (
    select
        c.from_ccy as from_ccy, c.to_ccy as to_ccy, c.rate as rate, c.expected as expected,
        {{ fx_magnitude_problem('c.rate', 'c.from_ccy', 'c.to_ccy', 'f.usd_log10', 't.usd_log10') }} as problem
    from cases as c
    left join ref_mag as f on f.currency_code = c.from_ccy
    left join ref_mag as t on t.currency_code = c.to_ccy
)

select *, multiIf(problem = '', 'ok', startsWith(problem, 'no reference'), 'no_reference',
                  startsWith(problem, 'more than 10x'), 'implausible', 'invalid') as got
from checked
where got != expected
