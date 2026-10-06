{# The materiality floor (konsolidat#209): the half-cent below which an
   amount is treated as zero when posting or reconciling. One definition, so
   a later change (a group-declared floor, a currency-scaled floor) is one
   edit. In SQL write {{ materiality_floor() }}; inside a Jinja expression,
   materiality_floor(). tests/test_materiality_literal.py keeps the literal
   out of every other model, macro and test. #}
{% macro materiality_floor() %}0.005{% endmacro %}

{# konsolidat#245, PR #260 re-review finding 1. How divisible a side must be
   before its elimination leg is apportioned across its slices.

   The first attempt guarded with materiality_floor(), which is an ABSOLUTE
   amount (0.005) and the wrong instrument for a RATIO. A side of +1000.00 and
   -999.99 nets to 0.01 — twice the floor — so it was apportioned, giving shares
   of 100000 and -99999 and turning a -1000 leg into -100,000,000 and
   +99,999,000. Every total stayed correct and every assertion passed.

   A side is divisible only when its NET movement is a meaningful fraction of
   its GROSS: abs(sum(slice)) >= DIVISIBLE_SHARE * sum(abs(slice)). At 0.01 the
   largest share any slice can take is 100, so an apportioned leg is bounded at
   100x its own amount instead of unbounded.

   Below the bound the side's slices cancel each other and there is no honest
   way to attribute the leg between them, so the whole leg goes on ONE blank
   slice. That is a declared loss of detail, not a silent one: it is the same
   answer this layer gives for a side it knows nothing about, and
   assert_ic_elimination_share_is_bounded tests the bound. #}
{% macro divisible_share() %}0.01{% endmacro %}
