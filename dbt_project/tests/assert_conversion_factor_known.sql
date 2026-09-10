{#
    Every ConversionFactor value must be one the D365 adapter resolves.

    The adapter's else-branch passes an unrecognised factor through unscaled —
    the exact silent-scaling failure class of #138, one enum value away. This
    test turns that into a build failure instead. Extend the adapter's multiIf
    AND this list together when D365 grows a new display factor.
#}

select
    ConversionFactor as conversion_factor,
    count() as rows
from {{ source('d365_raw', 'exchange_rates') }}
where coalesce(toString(ConversionFactor), 'One')
      not in ('One', 'Ten', 'Hundred', 'Thousand', 'TenThousand')
group by 1
