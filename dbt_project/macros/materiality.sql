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

{# konsolidat#209 (Deepak Pai, 18 Sep 2026: materiality follows the currency's
   ISO minor unit; a flat default was rejected). THE ONE PATH from a group to
   its currency's minor unit: the group's reporting currency on its root row
   (data_area_id '') and the currencies row konsol writes from ISO
   Currency.minor_unit. A relation, one row per group that HAS a minor unit.

   An INNER JOIN on purpose. join_use_nulls=0 would fill a missing minor unit
   with 0 (the JPY scale) and nobody could tell it from a declared 0, so a
   caller that needs every group LEFT JOINs this relation and reads
   has_minor_unit, which is 0 only on a join miss. A group not in it is
   refused or reported by the caller's test, never judged at a default:
   assert_topside_journal_balanced ('no currency') and
   assert_ic_group_currency_has_minor_unit. #}
{% macro group_minor_units() -%}
(select
     g.consolidation_group as consolidation_group,
     any(g.reporting_currency) as currency,
     toInt32(any(c.minor_unit)) as minor_unit,
     toUInt8(1) as has_minor_unit
 from {{ source('epm_gold', 'consolidation_groups') }} as g
 inner join {{ source('epm_gold', 'currencies') }} as c
     on c.currency_code = g.reporting_currency
 where g.data_area_id = ''
 group by g.consolidation_group)
{%- endmacro %}

{# konsolidat#395, decided 27 Nov 2026 by Deepak Pai: option B (rejected: A,
   a fixed 4 places with its limit stated; C, summing these layers in
   Decimal). The 1B coverage comparison, at the GROUP CURRENCY's ISO minor
   unit. THE ONE DEFINITION: gold_fully_consolidated_tb (the to-date split and
   both legs of the period split) and assert_ic_slice_to_date_eliminated all
   write {{ ic_leg_covered(aligned_gross, leg, minor_unit, has_minor_unit) }},
   so the test and the model cannot decide a side differently. minor_unit and
   has_minor_unit come from group_minor_units(), LEFT JOINed on the group.

   Why rounded. IC is eliminated in full, so aligned_gross equals |leg| in
   exact arithmetic at every point, and the comparison sits on its edge. Both
   sides are Float64 sums, and ClickHouse adds in parallel in no fixed order,
   so each lands a little above or below the true value (~5e-10 measured on an
   example). Unrounded, a sum that landed below gave "not covered" and moved
   the WHOLE leg to the blank slice, and a rebuild could decide the other way.
   Two periods of 0.1 and 0.2 make a leg of 0.30000000000000004 against a
   slice of 0.3.

   Why the minor unit, not a fixed scale. This follows the 18 Sep 2026
   decision that materiality follows the currency's minor unit (konsolidat#209).
   Float64 error grows with the size of the sum, so a fixed 4 places absorbs
   it only while it stays below 0.00005: a simulation of two summation orders
   over 200 two-place amounts gave rounded results that differ from sums of
   about 1e10, ordinary in JPY, KRW, IDR or VND. At the minor unit it gave 0
   differences up to 1e13. Rounding is round(x * 10^minor_unit) on both sides,
   not round(x, minor_unit), so the scale may be a column.

   What it accepts (the trade-off decided with B):
     * Both sides are rounded, so a side is split when its aligned gross is up
       to ONE minor unit short of the leg, and its slices then take up to one
       minor unit more, in total, than they moved. With amounts at the minor
       unit the true sums are whole units and the shortfall is 0; it can be
       non-zero only for amounts finer than the unit (translated amounts).
     * The remaining limit is Float64 noise against one minor unit: past about
       1e13 group-currency units, or on a true value that falls exactly on a
       half unit, the two rounded sums can still differ.
     * A group with no minor unit (no reporting currency, or one with no
       currencies row) is never split: has_minor_unit = 0 makes the side "not
       covered", so the whole leg goes on the blank slice, and
       assert_ic_group_currency_has_minor_unit refuses the build, naming the
       group and the currency. #}
{% macro ic_leg_covered(aligned_gross, leg, minor_unit, has_minor_unit) -%}
({{ has_minor_unit }} = 1 and round({{ aligned_gross }} * pow(10, {{ minor_unit }})) >= round({{ leg_coverage() }} * abs({{ leg }}) * pow(10, {{ minor_unit }})))
{%- endmacro %}
