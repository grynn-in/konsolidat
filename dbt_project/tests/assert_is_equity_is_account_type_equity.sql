-- konsolidat#213: is_equity says what the account IS — the chart types it as Equity — which is the
-- meaning konsol's deal layer uses (business_combination.py: account_type == "Equity"). What the
-- chart DECLARES about translation is a separate fact with its own column, uses_historical_rate.
-- Deriving is_equity from fx_method conflated the two, so an asset declared at the historical rate
-- read as equity and would have been eliminated as pre-acquisition equity by the acquisition journal.
-- One row per account whose flags disagree with its declaration.
select
    main_account_id,
    account_type,
    fx_method,
    is_equity
from {{ ref('silver_main_accounts') }}
where is_equity != toUInt8(account_type = 'Equity')
