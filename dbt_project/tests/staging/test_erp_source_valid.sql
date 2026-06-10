{#
    Assert erp_source in canonical GL entries only contains allowed values.
    Returns rows with invalid erp_source values.
#}

select
    erp_source,
    count(*) as row_count
from {{ ref('stg_gl_entries') }}
where erp_source not in ('d365_fo', 'd365_bc', 'sap_s4', 'sap_ecc', 'sap_b1', 'erpnext')
group by erp_source
