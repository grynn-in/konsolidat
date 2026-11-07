{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# F2: the ONE resolved answer to "how much of this entity does this group own,
   in this period, and how is it consolidated".

   Two things were wrong before, and they compounded:

   1. Ownership lived in three places — the consolidation_groups seed, the
      consolidation_hierarchy staging table, and ownership_periods — with an
      ad-hoc `if(x != 0, ...)` chain choosing between them that read a genuine
      0% as "unset". Ownership is now temporal and lives only in Ownership
      Period; Consolidation Group is structure.

   2. The tree was stored and never traversed. Every consolidated model joined
      an entity to its IMMEDIATE parent group only, so GROUP_CORP's consolidated
      result contained JPMF and USMF and none of GROUP_EMEA's entities — at any
      percentage. `effective_ownership_pct` was a column name, not a
      computation: konsol wrote the direct percentage into it.

   The link closure (epm_staging.consolidation_ancestry, written by konsol's
   tree walk) carries one row per (ancestor group, entity, link between them).
   Multiplying each link's dated percentage gives the effective share, and
   emitting a row per ancestor is what makes consolidation multi-level: a
   60%-owned subsidiary of an 80%-owned sub-group reaches the top group at 48%.

   A chain is only usable if EVERY link resolves to a period covering the date.
   One missing link yields effective 0 and `has_complete_chain = 0` rather than
   a plausible-looking number — assert_ownership_chain_complete fails the build
   and names the entity. #}

{# The periods an entity actually HAS data in — per entity, not a global spine.
   A global spine crossed every link with every period in the warehouse, so an
   entity acquired in 2025 came out with an unresolvable chain for every period
   back to 2019 and a disposed one for every period after it left, and
   assert_ownership_chain_complete failed the build on all of them.

   No period_filter here either. This model is materialized `table`, and
   gold_nci_movement_schedule and gold_equity_method_associates are plain tables
   that now inner-join it on (fiscal_year, fiscal_period): filtering to one
   period during a scoped close would rebuild both holding that period alone and
   silently drop every prior period's NCI schedule and equity entries. The
   consolidation chokepoint downstream still applies its own filter, and
   gold_trial_balance is deliberately unscoped. #}
with entity_periods as (
    select distinct
        data_area_id,
        fiscal_year,
        fiscal_period,
        {{ build_date_from_year_period('fiscal_year', 'fiscal_period') }} as period_date
    from {{ ref('gold_trial_balance') }}
),

{# The graph itself is resolved by ownership_resolution_ctes (macros/
   ownership_resolution.sql), which gold_ic_reconciliation also uses on a
   period spine of its own. What each step does, and why:

   - ownership: Nullable throughout. An ASOF LEFT JOIN miss is filled with the
     column DEFAULT (0 / '' / 1970-01-01), not NULL, so without this a node
     with no ownership period would read as a real 0%, indistinguishable from
     a deliberate deconsolidation. The same defaulting trap the FX and
     historical-rate blocks in gold_consolidated_trial_balance guard against.
   - link_history: does this LINK (owned node, owner node) have any ownership
     history at all? "We know when we held it and this is not it" (before an
     acquisition, after a disposal) is a deliberate 0, not a missing
     percentage. Consolidation excludes it either way, but only the latter is
     worth failing a build over.
   - links: ASOF picks the latest period whose effective_date <= period_date,
     matched on both the owned and the owning node (konsol#117: two owners of
     one node are two links); end_date is then checked explicitly, because
     ASOF cannot carry a second inequality and would otherwise keep applying
     an expired period forever.
   - paths: one row per path_id: the product of its links, the weakest link's
     method (a sub-group held at equity is not line consolidated into its
     parent, so nothing beneath it is either; an unrecognised or unresolved
     method ranks as the strictest rather than silently as 'full'), and its
     direct link, the one into the entity's own node.
   - resolved: the paths summed. effective = sum of the resolved paths'
     products; direct = the sum of the DISTINCT links into the entity's node;
     owner_group is the consolidation_group of the entity's own node, as
     before (a historical equity rate is recorded once, under that node, and
     konsol validates it against it); path_count and direct_owner_count tell
     a reader how the number was reached and how many nodes hold the entity.
   - ruled / resolution: the method rule of design section 2 (konsol#117).
     One path, or several whose links agree with an all-full path among them
     or a sum within DECLARATION_TRIGGER_PCT: the links decide ('link').
     Otherwise the group's declaration decides ('declared'), read ASOF from
     consolidation_method_declarations; required and absent is 'undeclared'
     with method 'none', so nothing consolidates and
     assert_method_declared_for_multi_path names it. has_complete_chain is 1
     when at least one path resolves and no path has an unrecorded link;
     outside_ownership_window is 1 when no path resolves but every link has
     history, i.e. we did not own it then. It distinguishes a deliberate gap
     from an unrecorded one; assert_ownership_chain_complete only fails on
     the latter. #}
{{ ownership_resolution_ctes('entity_periods') }}

select * from resolution
