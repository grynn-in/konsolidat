{# Maps D365 MainAccountType enum (numeric or string) to readable name #}
{% macro map_account_type(column) %}
    case {{ column }}
        when '0' then 'Profit and loss'
        when '1' then 'Revenue'
        when '2' then 'Expense'
        when '3' then 'Balance sheet'
        when '4' then 'Asset'
        when '5' then 'Liability'
        when '6' then 'Equity'
        when '7' then 'Total'
        when 'ProfitAndLoss' then 'Profit and loss'
        when 'Revenue' then 'Revenue'
        when 'Expense' then 'Expense'
        when 'BalanceSheet' then 'Balance sheet'
        when 'Asset' then 'Asset'
        when 'Liability' then 'Liability'
        when 'Equity' then 'Equity'
        when 'Total' then 'Total'
        else {{ column }}
    end
{% endmacro %}
