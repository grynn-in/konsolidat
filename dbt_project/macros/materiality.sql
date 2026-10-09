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

{# konsolidat#245, decision 1B (Deepak Pai, 9 Oct 2026). How much of a leg a
   side's own activity must cover before the leg is apportioned across that
   side's slices.

   The gate has to relate to the LEG, not to the side alone. Four earlier
   attempts put an absolute floor on the side (half a cent, then a ratio of the
   side's own net to its own gross) and each one let a side with almost no
   activity split a very large leg: measured, a side with 0.008 of movement
   divided a -1,000,000 elimination into -500,000 per cost centre. A side
   cannot explain a leg its own activity does not account for.

   At 0.5 a side must have moved at least half the leg before its slices are
   used to divide it. Below that the whole leg goes on ONE blank slice — the
   same answer this layer gives for a side it knows nothing about, and a
   declared loss of detail rather than an invented split. #}
{% macro leg_coverage() %}0.5{% endmacro %}
