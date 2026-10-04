-- konsolidat#245 option D, decided by Deepak Pai on 3 October 2026: a
-- consolidation entry carries the dimension values of whatever knows them. The
-- four deal-journal layers of gold_fully_consolidated_tb — acquisition,
-- business combination, goodwill amortisation and disposal — know none. Their
-- inputs are the Business Combination and Business Disposal documents, which
-- carry no dimension fields and have no slice to inherit from, so their rows
-- are blank BY DECISION and nothing should be invented for them.
--
-- "Blank by decision" is worth asserting, because it is indistinguishable in
-- the data from "blank because somebody forgot" — which is what the other eight
-- layers were before this issue. If a deal layer ever starts carrying a value,
-- either someone gave those documents a dimension (then this test is the place
-- to record the new decision) or a layer is reading a slice it cannot know.
--
-- One row per offending layer and dimension. Error severity: a value here is
-- not a data-quality warning, it is a layer claiming knowledge it does not have.
{% set dims = var('dimensions') %}
{% if dims | length == 0 %}
select 1 as adjustment_type where 0
{% else %}
select
    adjustment_type,
    '{{ dims | map(attribute="name") | join(", ") }}' as checked_dimensions,
    count() as rows_carrying_a_value
from {{ ref('gold_fully_consolidated_tb') }}
-- The four values the deal models emit, read from them rather than guessed:
-- gold_acquisition_adjustments 'pnl_proration', gold_business_combination_journal
-- 'acquisition', gold_goodwill_amortisation_journal 'goodwill_amortisation',
-- gold_business_disposal_journal 'disposal'.
where adjustment_type in (
        'pnl_proration', 'acquisition', 'goodwill_amortisation', 'disposal')
  and (
    {%- for d in dims %}
    {{ d.name }} != ''{{ ' or' if not loop.last }}
    {%- endfor %}
  )
group by adjustment_type
{% endif %}
