{#
    Assert key columns in canonical GL entries are not null.
    Returns rows where any key column is null.
#}

select
    record_id,
    entity_id,
    posting_date,
    main_account,
    erp_source
from {{ ref('stg_gl_entries') }}
where record_id is null
   or entity_id is null
   or entity_id = ''
   or posting_date is null
   or main_account is null
   or main_account = ''
   or erp_source is null
   or erp_source = ''
