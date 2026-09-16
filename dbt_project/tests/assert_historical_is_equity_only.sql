{#
    konsolidat#92, finding 4 — the half the warehouse owns.

    konsol translates and does not remeasure. fx_method = 'historical' is
    therefore an Equity-only declaration: an Asset or Liability carried at the
    rate of the day it arrived would be remeasurement (IAS 21's non-monetary
    treatment), which this product does not do. konsol#239 refuses any such
    declaration at publish, so a chart governed today cannot carry one.

    A stack whose chart predates that guard still can, and that is what this
    test is for. The damage is not that the number is wrong in an obvious way:
    gold_consolidated_trial_balance applies a historical rate only where the
    chart declares one, so a Historical Equity Rate keyed to a non-equity
    account is simply never applied and the balance quietly falls back to the
    closing rate. Silent is the problem. This names the declaration instead.

    Error, not warn. assert_equity_rate_coverage warns because every row it
    returns is master data with a defined fallback (equity with no historical
    rate translates at closing, which is a decision, not a mistake). A
    historical declaration on a non-equity account has no such reading: it is
    a wrong declaration, and the fallback it lands on is not what the chart
    asked for. Nothing downstream can repair it, so the build should stop.

    GREEN requires every account declaring historical to be typed Equity —
    the konsolidat#213 invariant, uses_historical_rate = 1 implies
    is_equity = 1. is_equity is what the account IS (account_type = 'Equity');
    uses_historical_rate is what the chart DECLARES (fx_method = 'historical').

    Two kinds of offender, one row each, the assert_staging_not_stale shape:

    DECLARATION — the chart itself, an account typed non-equity that declares
    historical. One row per account.

    RATE — a Historical Equity Rate someone entered against an account that is
    not equity. The chart is where the damage is, but the rate is the row a
    user typed and expects to see honoured, and it can outlive the declaration
    that made it plausible (retype the account and the rate simply stops
    mattering, still sitting there). It is never applied either way, so name it
    too. One row per rate row, tranches included: each is a separately entered
    rate that does nothing.
#}

select
    'DECLARATION' as kind,
    ''           as consolidation_group,
    ''           as data_area_id,
    main_account_id,
    concat(
        'main account ', main_account_id, ' (', account_name, ') is typed ',
        account_type, ' but declares fx_method = ', fx_method,
        ' — konsol translates and does not remeasure, so only an Equity account',
        ' may declare the historical rate (konsol#239 refuses this at publish).',
        ' As declared, a Historical Equity Rate for this account is never applied:',
        ' gold_consolidated_trial_balance applies one only where the chart declares',
        ' it, and the balance falls back to the closing rate. Retype the account as',
        ' Equity, or declare it at the closing rate, in the konsol Main Account.'
    ) as problem
from {{ ref('silver_main_accounts') }}
where uses_historical_rate = 1
  and is_equity = 0

union all

{# The rate half of finding 4. gold_consolidated_trial_balance joins
   historical_equity_rates on (owner group, data_area_id, main_account) and then
   applies the joined rate only where `etb.fx_method = 'historical'`, fx_method
   being the chart's. So a rate keyed to an account the chart does not type as
   equity is read, dropped, and never mentioned: the balance translates at the
   closing rate as if the rate had never been entered. "Not an equity account"
   covers both readings of the same mistake — an account the chart types as
   something else, and an account the chart does not carry at all (mistyped
   code, an account since deleted), which is equally inert. #}
select
    'RATE' as kind,
    r.consolidation_group,
    r.data_area_id,
    r.main_account as main_account_id,
    concat(
        'consolidation group ', r.consolidation_group, ', entity ', r.data_area_id,
        ': the Historical Equity Rate for main account ', r.main_account,
        ' is ignored — that account is not an Equity account of the governed chart,',
        ' and gold_consolidated_trial_balance applies a historical rate only where',
        ' the chart declares fx_method = historical. The balance translates at the',
        ' closing rate as though this rate did not exist (konsolidat#92 finding 4).',
        ' Either the account is equity and the chart should type it so, or the rate',
        ' belongs to a different account and should be cancelled.'
    ) as problem
from {{ source('epm_staging', 'historical_equity_rates') }} as r
where r.main_account not in (
    select main_account_id
    from {{ ref('silver_main_accounts') }}
    where is_equity = 1
)
