{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id)'
    )
}}

{# konsol#110 — which currency each entity keeps its books in. The one answer.

   One source: epm_staging.entities, konsol's Entity master (functional_currency),
   written through on every save. Leaves only; a group keeps no books.

   konsolidat#255 (option #255-1, Deepak Pai, 11 Oct 2026): there is no ERP
   fallback. This model used to fill a blank functional currency from
   silver_legal_entities, the ERP's company master. Since konsol#328 trial-balance
   intake refuses an Entity with no Functional Currency, so the warehouse was
   resolving a currency intake declares unknown. A blank stays blank here:
   consolidation joins only resolved currencies, and
   assert_every_tb_entity_has_a_currency names an entity with trial-balance rows
   and none. Rejected: #255-2, leaving the fallback to the ERP removal (#221).
   Measured on live before the change: silver_legal_entities had 0 rows, so the
   fallback resolved nothing.

   GROUP BY so a duplicate Entity row cannot fan out a consolidation join.
   anyIf skips a blank row in favour of a set one; over no set row it yields ''
   (a String default, not NULL), which is what the consumers filter on. #}

select
    data_area_id,
    anyIf(accounting_currency, accounting_currency != '') as accounting_currency
from {{ source('epm_staging', 'entities') }}
where is_group = 0
group by data_area_id
