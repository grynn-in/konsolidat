{{ config(severity='warn') }}
{#
    konsol#182: every translated row uses the rate its account DECLARES in the
    konsol group chart (fx_method): historical takes the as-of historical
    equity rate (the closing rate before the first tranche), average the
    period average rate, closing, and an undeclared account, the closing rate.
    A P&L account declared at closing (IAS 29) is right at the closing rate,
    which is why this replaces assert_bs_uses_closing_rate and
    assert_pnl_uses_average_rate: they tied the rate to the statement.

    Translated rows only: a same-currency entity translates at 1.0 by
    definition. Tolerance 1e-6.

    The LEFT JOIN is safe here: under join_use_nulls=0 an undeclared account's
    fx_method is '', which expects the closing rate, exactly as the model does.

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model's downstream,
    leaving the old figures in place and the run half-green.
#}
select
    ctb.consolidation_group,
    ctb.data_area_id,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.main_account,
    ma.fx_method as declared_fx_method,
    ctb.translation_rate,
    multiIf(
        ma.fx_method = 'historical' and ctb.historical_equity_rate is not null, ctb.historical_equity_rate,
        ma.fx_method = 'average', ctb.average_rate,
        ctb.closing_rate
    ) as expected_rate
from {{ ref('gold_consolidated_trial_balance') }} as ctb
left join (
    select main_account_id, fx_method from {{ ref('silver_main_accounts') }}
) as ma
    on ctb.main_account = ma.main_account_id
where ctb.accounting_currency != ctb.reporting_currency
  and abs(ifNull(ctb.translation_rate, 0) - ifNull(expected_rate, 0)) > 0.000001
