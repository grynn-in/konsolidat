-- PRD-22 Test: the fully consolidated trial balance must balance end to end —
-- total debits ≈ total credits across ALL layers (entity translation + IC
-- elimination + CTA + topside + equity method + acquisition/disposal).
--
-- This sums every account, not just balance-sheet ones. gold_fully_consolidated_tb
-- is a per-period MOVEMENT trial balance, so the balance-sheet movements alone do
-- NOT net to zero — they net to the period's net income (which lives in the open
-- P&L accounts, not yet closed to equity). The meaningful double-entry invariant
-- is therefore that the WHOLE TB nets to zero: every asset/liability/equity
-- movement has its counterpart somewhere in the same TB (the P&L that drives
-- equity, plus the CTA that absorbs the FX translation difference). When this
-- holds, the consolidated balance sheet and cash flow tie. The earlier BS-only
-- form passed only because every group consolidated to zero (rate/ownership bugs);
-- it never actually exercised this invariant.
select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    sum(amount) as net_balance
from {{ ref('gold_fully_consolidated_tb') }}
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(amount)) > 1.00
