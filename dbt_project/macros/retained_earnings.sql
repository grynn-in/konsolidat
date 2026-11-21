{#
  retained_earnings_account() -- the chart's retained-earnings account (konsolidat#316, option A).

  Returns a one-row subquery: use it as `(...) as re` in a FROM / JOIN.
      retained_earnings_account  the main_account_id flagged is_retained_earnings
      re_count                   how many accounts carry the flag

  The account is usable ONLY when re_count = 1. With 0 flagged there is none; with 2 or more any
  pick (lowest code, anyIf) is a silent policy decision. Callers therefore post nothing when
  re_count != 1 and never fall back, and `assert_retained_earnings_account_unique` fails the
  build naming each consolidation group that has journal rows while the count is not 1.
  Same rule as silver_tb_movements (#259 close): skip unless exactly one account is flagged.
  When count() is 0 the aggregate still yields one row (retained_earnings_account = '').
#}
{% macro retained_earnings_account() %}
(
    select
        count() as re_count,
        any(main_account_id) as retained_earnings_account
    from {{ ref('silver_main_accounts') }}
    where is_retained_earnings = 1
)
{% endmacro %}
