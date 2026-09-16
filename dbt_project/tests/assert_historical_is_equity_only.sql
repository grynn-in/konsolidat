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
#}

select
    main_account_id,
    account_name,
    account_type,
    fx_method,
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
