-- konsol#305-D2-11: every line of an Approved journal that names a reversal
-- period has an auto_reversal row in exactly that period, and no auto_reversal
-- row exists without one. NOT IN, never LEFT JOIN ... is null: under
-- join_use_nulls=0 a miss reads '' and the old guard could never fail.
select 'missing' as fault, journal_id, data_area_id, main_account,
       reverse_fiscal_year as fiscal_year, reverse_fiscal_period as fiscal_period
from {{ source('epm_staging', 'consolidation_adjustments') }}
where status = 'Approved' and reverse_fiscal_year > 0
  and (journal_id, data_area_id, main_account, reverse_fiscal_year, reverse_fiscal_period) not in (
      select journal_id, data_area_id, main_account, fiscal_year, fiscal_period
      from {{ ref('gold_consolidation_adjustments') }} where adjustment_type = 'auto_reversal')
union all
select 'orphan' as fault, journal_id, data_area_id, main_account, fiscal_year, fiscal_period
from {{ ref('gold_consolidation_adjustments') }}
where adjustment_type = 'auto_reversal'
  and (journal_id, data_area_id, main_account, fiscal_year, fiscal_period) not in (
      select journal_id, data_area_id, main_account, reverse_fiscal_year, reverse_fiscal_period
      from {{ source('epm_staging', 'consolidation_adjustments') }}
      where status = 'Approved' and reverse_fiscal_year > 0)
