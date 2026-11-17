{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# konsol#117 pair 2 K2 (konsolidat#204 option (a), IFRS 10.B86 / B94; decided by
   Deepak Pai, 7-8 Nov 2026): the minority's share of a subsidiary's result and
   currency translation difference, attributed to the NCI line.

   Why. Since K1 a full-method subsidiary is consolidated line by line at 100%
   (group_amount = translated_amount), and K3 eliminates intercompany balances in
   full. The minority's interest is then one equity line, and the profit and CTA
   the group's own equity lines carry must be reduced by the minority's part
   (IFRS 10.B94: profit or loss and each component of OCI are attributed to the
   owners of the parent and to the non-controlling interests). This model posts
   that attribution; it is layer 'nci_attribution' of gold_fully_consolidated_tb.

   One journal per (group, entity, FY, period), journal_id
   'NCI-{group}-{entity}-{FY}-P{period}', adjustment_type 'nci_attribution',
   data_area_id the subsidiary, dimensions blank, for every row of
   gold_entity_ownership with consolidation_method 'full', effective ownership
   below 100% and a complete chain, that has rows in the consolidated TB for the
   period:
     result_share = sum of nci_amount over the entity-period's P&L rows of
                    gold_consolidated_trial_balance, year-end close rows excluded
                    ( = (1 - ownership) x the period's translated P&L);
     cta_share    = (1 - ownership) x the entity's CTA plug of the period
                    (gold_fx_revaluation; 0 when it has no row).
   Lines (Dr positive; a profit is a credit, so result_share is negative):
     retained-earnings account  -result_share   Dr RE on a profit
     'CTA'                      -cta_share
     the group's nci_account    result_share + cta_share
   Sums to zero by construction. A zero line is omitted; a journal whose two
   shares are both 0 is omitted.

   Year-end close. The close silver_tb_movements synthesizes in a Closing period
   (konsolidat#259) moves the year's P&L into retained earnings. Summed as the
   period's result it would reverse the year's attribution in P13. The marker
   gold_trial_balance_by_partner.is_year_end_close = 1 is joined by (entity, FY,
   period, main_account), as gold_equity_method_associates does (konsolidat#279
   defect 3): a key's close rows are never mixed with activity in one period.
   The close period carries the share of its own activity, or no journal.

   No home, no journal. The retained-earnings account is the chart's
   silver_main_accounts.is_retained_earnings = 1, read through the macro
   retained_earnings_account() (konsolidat#316): when the chart flags none or
   several, the RE line is posted on '' (the journal stays balanced) and
   assert_retained_earnings_account_unique flags the group. A group whose root
   declares no nci_account gets NO journal (inner join); assert_nci_attribution_equals_
   minority_result flags the missing figure and
   assert_nci_account_declared_for_partial_subs warns about the group.

   Legacy subsidiaries (owned before the first TB) have no deal journal: their
   OPENING NCI is the site's own opening elimination journal (topside), not the
   tool's. An acquired subsidiary's opening NCI comes from
   gold_business_combination_journal line (5). This layer attributes only the
   POST-acquisition movements of each period.

   NOT attributed in pair 2 (follow-up issues): the minority's share of equity
   movements inside the subsidiary (dividends to the NCI, capital changes), and
   the pre-acquisition part of the P&L in the acquisition period (prorated out). #}

with scope as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        eo.effective_ownership_pct as ownership_pct
    from {{ ref('gold_entity_ownership') }} as eo
    where eo.consolidation_method = 'full'
      and eo.has_complete_chain = 1
      and eo.effective_ownership_pct < 1 - 0.000001
),

{# Periods in which the entity has rows in the consolidated TB. #}
present as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_consolidated_trial_balance') }}
),

{# Accounts whose rows in a period are the synthesized year-end close. #}
close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
),

result as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(toFloat64(nci_amount)) as result_share
    from {{ ref('gold_consolidated_trial_balance') }}
    where is_pnl = 1
      and (data_area_id, fiscal_year, fiscal_period, main_account)
          not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys)
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

cta as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(toFloat64(cta_amount)) as cta_amount
    from {{ ref('gold_fx_revaluation') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period
),

{# Unmatched LEFT JOINs fill 0 under join_use_nulls = 0: no result row or no
   plug row reads as a zero share, which is what is meant. #}
shares as (
    select
        s.consolidation_group as consolidation_group,
        s.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period,
        r.result_share as result_share,
        (1.0 - s.ownership_pct) * c.cta_amount as cta_share
    from scope as s
    inner join present as p
        on p.consolidation_group = s.consolidation_group
        and p.data_area_id = s.data_area_id
        and p.fiscal_year = s.fiscal_year
        and p.fiscal_period = s.fiscal_period
    left join result as r
        on r.consolidation_group = s.consolidation_group
        and r.data_area_id = s.data_area_id
        and r.fiscal_year = s.fiscal_year
        and r.fiscal_period = s.fiscal_period
    left join cta as c
        on c.consolidation_group = s.consolidation_group
        and c.data_area_id = s.data_area_id
        and c.fiscal_year = s.fiscal_year
        and c.fiscal_period = s.fiscal_period
    where abs(r.result_share) > 0.000001 or abs((1.0 - s.ownership_pct) * c.cta_amount) > 0.000001
),

group_nci as (
    {{ ic_group_nci_accounts() }}
),

{# The chart's single retained-earnings account (konsolidat#316, macro retained_earnings_account()).
   With 0 or 2+ accounts flagged there is no single account: the RE line is posted on '' (never a
   lowest-code guess) so the journal stays balanced, and assert_retained_earnings_account_unique
   names the group. #}
re_account as (
    select
        if(r.re_count = 1, r.retained_earnings_account, '') as re_account,
        if(r.re_count = 1, any(a.account_name), '') as re_name
    from {{ retained_earnings_account() }} as r
    left join {{ ref('silver_main_accounts') }} as a
        on a.main_account_id = r.retained_earnings_account
    group by r.re_count, r.retained_earnings_account
),

nci_names as (
    select main_account_id, any(account_name) as account_name
    from {{ ref('silver_main_accounts') }}
    group by main_account_id
),

journal as (
    select
        sh.consolidation_group as consolidation_group,
        sh.data_area_id as data_area_id,
        sh.fiscal_year as fiscal_year,
        sh.fiscal_period as fiscal_period,
        sh.result_share as result_share,
        sh.cta_share as cta_share,
        gn.declared_nci_account as nci_account,
        if(nn.account_name = '', gn.declared_nci_account, nn.account_name) as nci_name,
        re.re_account as re_account,
        re.re_name as re_name,
        grp.reporting_currency as reporting_currency,
        concat('NCI-', sh.consolidation_group, '-', sh.data_area_id, '-',
               toString(sh.fiscal_year), '-P', toString(sh.fiscal_period)) as journal_id
    from shares as sh
    inner join group_nci as gn
        on gn.nci_group = sh.consolidation_group
        and gn.declared_nci_account != ''
    cross join re_account as re
    left join nci_names as nn
        on nn.main_account_id = gn.declared_nci_account
    left join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = sh.consolidation_group
        and grp.data_area_id = ''
)

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    re_account as main_account,
    re_name as account_name,
    reporting_currency,
    -result_share as amount,
    'nci_attribution' as adjustment_type,
    journal_id,
    'retained_earnings' as account_role
from journal
where abs(result_share) > 0.000001

union all

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    'CTA' as main_account,
    'CTA' as account_name,
    reporting_currency,
    -cta_share as amount,
    'nci_attribution' as adjustment_type,
    journal_id,
    'cta' as account_role
from journal
where abs(cta_share) > 0.000001

union all

select
    consolidation_group, data_area_id, fiscal_year, fiscal_period,
    nci_account as main_account,
    nci_name as account_name,
    reporting_currency,
    result_share + cta_share as amount,
    'nci_attribution' as adjustment_type,
    journal_id,
    'nci' as account_role
from journal
where abs(result_share + cta_share) > 0.000001
