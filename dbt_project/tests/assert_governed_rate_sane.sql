{{ config(severity='warn') }}
{#
    konsol#103 / #138: a governed rate is a positive, true rate of plausible
    magnitude, of a governed type, between two different currencies. konsol
    refuses each of these at entry (konsol.group_rates.magnitude_problem for
    the magnitude); this names a row that reached the warehouse another way
    (a script, a restore). The magnitude rule is macros/fx_magnitude.sql.

    severity warn: an error-severity source test would make `dbt build` skip
    the model; the model's own guard decides whether the build fails.
#}

with ref_mag as {{ fx_reference_magnitudes() }},

checked as (
    select
        g.to_currency as to_currency,
        g.from_currency as from_currency,
        g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period,
        g.rate_type as rate_type,
        g.rate as rate,
        g.document as document,
        multiIf(
            g.from_currency = g.to_currency, 'a rate from a currency into itself',
            g.rate_type not in ('Closing', 'Average'), 'not a governed rate type',
            {{ fx_magnitude_problem('g.rate', 'g.from_currency', 'g.to_currency', 'f.usd_log10', 't.usd_log10') }}
        ) as problem
    from {{ source('epm_staging', 'group_exchange_rates') }} as g
    left join ref_mag as f on f.currency_code = g.from_currency
    left join ref_mag as t on t.currency_code = g.to_currency
)

select * from checked where problem != ''
