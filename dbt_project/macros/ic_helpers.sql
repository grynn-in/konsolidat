{# ============================================================
   Intercompany helpers (konsolidat#148, konsol#159)

   An account is intercompany because it is flagged in the group chart
   (decision 3, 13 Sep 2026): konsol's Intercompany Account doctype, written
   through to epm_staging.intercompany_accounts. Each Published row names an
   account and the counterpart the PARTNER books the other side on ('' = the
   same account). A pair is symmetric, so the counterpart is intercompany too.
   ============================================================ #}

{# One row per intercompany account: (account, counterpart). konsol refuses
   an account in two pairs; any() keeps this one-row-per-account even if a
   conflict slips through, and assert_ic_account_in_one_pair names it. #}
{% macro ic_account_map() %}
    select account, any(cp) as counterpart
    from (
        select
            main_account as account,
            if(counterpart_account = '', main_account, counterpart_account) as cp
        from {{ source('epm_staging', 'intercompany_accounts') }}
        where status = 'Published'
        union all
        select
            counterpart_account as account,
            main_account as cp
        from {{ source('epm_staging', 'intercompany_accounts') }}
        where status = 'Published'
          and counterpart_account != ''
          and counterpart_account != main_account
    )
    group by account
{% endmacro %}

{# Decision 12 (13 Sep 2026): the minority owners' portion of an eliminated
   intragroup balance goes to their line in the consolidated view, this
   account. A pseudo-account like DISPOSAL; set var ic_nci_account to post it
   to a chart account instead. #}
{% macro ic_nci_account() %}{{ var('ic_nci_account', 'NCI') }}{% endmacro %}

{# The partner-keyed slices of gold_consolidated_trial_balance, at 100%
   (translated_amount, never the ownership-weighted group_amount; and the
   entity's own local_amount), every period the entity is in the group view,
   whether or not its partner is yet: gold_ic_reconciliation applies the
   pair's membership (#175 re-review M1). The IC tests recompute from it. #}
{% macro ic_partner_slices() %}
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.partner_data_area_id as partner_data_area_id,
        ctb.main_account as main_account,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        ifNull(toFloat64(sum(ctb.translated_amount)), 0) as translated,
        ifNull(toFloat64(sum(ctb.local_amount)), 0) as local
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    where ctb.partner_data_area_id != ''
      and ctb.partner_data_area_id != ctb.data_area_id
    group by
        ctb.consolidation_group, ctb.data_area_id, ctb.partner_data_area_id,
        ctb.main_account, ctb.fiscal_year, ctb.fiscal_period
{% endmacro %}

{# Each gold_ic_reconciliation row's two sides recomputed from
   ic_partner_slices() on the row's basis (decision 14): the balance to date
   for a balance-sheet pair (everything the side booked in the group view,
   from before the partner joined too), the period's movement for a P&L
   pair; 0 on a 'left' row, where the pair is no longer intragroup. #}
{% macro ic_expected_pair_values() %}
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sum(exp_a) as expected_a,
        sum(exp_b) as expected_b,
        sum(exp_local_a) as expected_local_a,
        sum(exp_local_b) as expected_local_b
    from (
        select
            r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
            r.fiscal_period as fiscal_period, r.entity_a as entity_a, r.account_a as account_a,
            r.entity_b as entity_b, r.account_b as account_b,
            if(r.pair_event = 'left', 0, s.translated) as exp_a, toFloat64(0) as exp_b,
            if(r.pair_event = 'left', 0, s.local) as exp_local_a, toFloat64(0) as exp_local_b
        from {{ ref('gold_ic_reconciliation') }} as r
        inner join ({{ ic_partner_slices() }}) as s
            on s.consolidation_group = r.consolidation_group
            and s.data_area_id = r.entity_a
            and s.partner_data_area_id = r.entity_b
            and s.main_account = r.account_a
        where if(r.basis = 'balance',
                 tuple(s.fiscal_year, s.fiscal_period) <= tuple(r.fiscal_year, r.fiscal_period),
                 s.fiscal_year = r.fiscal_year and s.fiscal_period = r.fiscal_period)

        union all

        select
            r.consolidation_group, r.fiscal_year, r.fiscal_period, r.entity_a, r.account_a,
            r.entity_b, r.account_b,
            toFloat64(0), if(r.pair_event = 'left', 0, s.translated),
            toFloat64(0), if(r.pair_event = 'left', 0, s.local)
        from {{ ref('gold_ic_reconciliation') }} as r
        inner join ({{ ic_partner_slices() }}) as s
            on s.consolidation_group = r.consolidation_group
            and s.data_area_id = r.entity_b
            and s.partner_data_area_id = r.entity_a
            and s.main_account = r.account_b
        where if(r.basis = 'balance',
                 tuple(s.fiscal_year, s.fiscal_period) <= tuple(r.fiscal_year, r.fiscal_period),
                 s.fiscal_year = r.fiscal_year and s.fiscal_period = r.fiscal_period)
    )
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
{% endmacro %}
