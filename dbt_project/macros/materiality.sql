{# The materiality floor (konsolidat#209): the half-cent below which an
   amount is treated as zero when posting or reconciling. One definition, so
   a later change (a group-declared floor, a currency-scaled floor) is one
   edit. In SQL write {{ materiality_floor() }}; inside a Jinja expression,
   materiality_floor(). tests/test_materiality_literal.py keeps the literal
   out of every other model, macro and test. #}
{% macro materiality_floor() %}0.005{% endmacro %}

{# konsolidat#245. REMOVED: divisible_share().

   It existed to bound how far a slice could be moved when a side's slices
   offset, and it did not work. Guarding the NET against the GROSS still
   allowed 50.5x — a -1000 leg became -50,500 and +49,500 — and the comment
   here claimed 100x, which was wrong in the other direction. Both the
   threshold and its justification ("there is no honest way to attribute the
   leg") were over-claims: an honest attribution does exist, and layer 2 now
   uses it. Shares are abs(slice) / gross, which is bounded by construction, so
   there is no ratio to threshold. See gold_fully_consolidated_tb layer 2. #}
