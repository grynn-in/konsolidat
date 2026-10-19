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

{# konsolidat#245, decision 1B (Deepak Pai, 9 Oct 2026), CONSTANT CORRECTED
   after review round 5.

   How much of a leg a side's own activity must cover before the leg is
   apportioned across that side's slices.

   IT IS 1.0, and that is arithmetic rather than taste. A slice receives
   |leg| x aligned_i / aligned_gross, so it receives no more than its own
   aligned movement exactly when aligned_gross >= |leg|. At the 0.5 I first
   wrote, the gate permitted |leg| <= 2 x aligned_gross — so a slice could take
   TWICE what it booked, and round 5 measured a cost centre that had ever
   booked +100 ending at -100 on an intercompany receivable, with the account
   total exactly right. That is the fourth time a guard on this layer BOUNDED
   magnification instead of removing it (100000x, then 50.5x, then 2x).

   1.0 is also what the next sentence always implied: a side cannot explain a
   leg its own activity does not account for. The 0.5 contradicted it, which is
   the same comment-versus-code mismatch round 3 found.

   Below the bound the whole leg goes on ONE blank slice — the same answer this
   layer gives for a side it knows nothing about, and a declared loss of detail
   rather than an invented split.

   assert_ic_slice_not_moved_past_its_own encodes the invariant directly, and
   is the only assertion in this layer that is not satisfied by construction. #}
{% macro leg_coverage() %}1.0{% endmacro %}
