-- konsol#305-D2-11: every auto_reversal lands on a declared Regular period
-- strictly after its journal's own period. konsol checks this when the journal
-- is approved; this catches a calendar changed afterwards.
with reversals as (
    select distinct journal_id, fiscal_year, fiscal_period
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type = 'auto_reversal'
),
originals as (
    select distinct journal_id, fiscal_year, fiscal_period
    from {{ ref('gold_consolidation_adjustments') }}
    where adjustment_type != 'auto_reversal'
)
select r.journal_id as journal_id, r.fiscal_year as fiscal_year, r.fiscal_period as fiscal_period,
       'not a declared Regular period' as fault
from reversals as r
where (r.fiscal_year, r.fiscal_period) not in (
    select fiscal_year, fiscal_period from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular')
union all
select r.journal_id, r.fiscal_year, r.fiscal_period, 'not after the journal''s own period'
from reversals as r
inner join originals as o on o.journal_id = r.journal_id
where (r.fiscal_year, r.fiscal_period) <= (o.fiscal_year, o.fiscal_period)
