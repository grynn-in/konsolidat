{{ config(severity='warn') }}

-- konsolidat#110: the canonical stg_gl_entries drops GL lines with an empty
-- legal entity (D365 ships ~11% of headers with an empty
-- SubledgerVoucherDataAreaId — those rows can't be attributed to an entity or
-- consolidated; the drop is correct, see stg_gl_entries.sql / #105). But the
-- drop was SILENT: a future extract regression that inflated the entity-less
-- ratio would be swallowed with no signal.
--
-- This surfaces the entity-less share of the D365 GL adapter and WARNS (build
-- log, non-fatal) if it exceeds a generous bound. Baseline ~11%; warns above
-- 20% so a regression can't hide, without failing the governed build on the
-- known-good baseline.

with c as (
    select
        count(*) as total,
        countIf(coalesce(entity_id, '') = '') as entity_less
    from {{ ref('stg_d365_fo__gl_entries') }}
)

select
    total,
    entity_less,
    round(100.0 * entity_less / nullIf(total, 0), 2) as entity_less_pct
from c
where total > 0
  and 100.0 * entity_less / nullIf(total, 0) > 20
