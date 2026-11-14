{# The consolidation waterfall's buckets (konsolidat#316 7h): each bucket is a
   column of gold_consolidation_waterfall and holds the gold_fully_consolidated_tb
   adjustment_types summed into it. One list: the model builds its columns from
   it and assert_waterfall_covers_every_adjustment_type reads it, so a new layer
   that no bucket holds is named by the test instead of leaving final_amount
   unexplained. #}
{% macro waterfall_buckets() %}
  {{ return({
      'entity': ['entity'],
      'ic_elimination': ['ic_elimination'],
      'cta': ['cta'],
      'topside': ['topside', 'reclassification', 'auto_reversal'],
      'equity_method': ['equity_method'],
      {# konsolidat#198 (row J6b): layer 6 is the three balanced deal journals, adjustment_type
         'acquisition' (gold_business_combination_journal), 'goodwill_amortisation'
         (gold_goodwill_amortisation_journal) and 'disposal' (gold_business_disposal_journal),
         plus the P&L proration gold_acquisition_adjustments still posts. The one-sided
         'goodwill' / 'fair_value_adjustment' / 'disposal_gain_loss' / 'cta_recycling' rows no
         longer exist; the names stay so an older build of the TB still sums. #}
      'acq_disposal': ['pnl_proration', 'acquisition', 'goodwill_amortisation', 'disposal',
                       'goodwill', 'fair_value_adjustment', 'disposal_gain_loss', 'cta_recycling']
  }) }}
{% endmacro %}

{% macro waterfall_bucketed_types() %}
  {% set types = [] %}
  {% for bucket, members in waterfall_buckets().items() %}
    {% for t in members %}{% do types.append(t) %}{% endfor %}
  {% endfor %}
  {{ return(types) }}
{% endmacro %}
