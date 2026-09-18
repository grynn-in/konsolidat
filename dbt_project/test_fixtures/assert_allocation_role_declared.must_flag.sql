-- konsolidat#220 R10: one Allocation Rule, so assert_allocation_role_declared has
-- something to report.
--
-- Without this fixture that test passes at zero dimensions for the wrong reason:
-- epm_staging.allocation_rules is empty on a fresh stack, so "no rows returned"
-- means "no rules exist", not "the rules are fine". A test that cannot fail is
-- exactly what konsolidat#220 has spent five instruments learning to distrust.
--
-- With this row loaded:
--   dimensions: []        -> the test returns 1 row and WARNS (the misconfiguration
--                            is named: a rule exists, no dimension declares the
--                            role). severity='warn', not error, so the allocation
--                            models still build — empty — and a consolidation-scope
--                            close is not blocked by it (konsol#264).
--   real dimensions       -> the site declares allocation_role: cost_center, the
--                            test asserts nothing and PASSES
--
-- ZZ-prefixed per the test-data convention: obviously fake, sorts last, and found
-- by cleanup with LIKE 'ZZ%'.

INSERT INTO epm_staging.allocation_rules
    (allocation_rule_id, rule_name, step_order, source_account, source_cost_center,
     driver_type, target_account, description, allocation_method, driver_formula, updated_at)
VALUES
    ('ZZ_ALLOC_R1', 'ZZ rule with no cost-centre dimension', 1, 'ZZ1000', 'ZZ_CC1',
     'headcount', 'ZZ2000', 'konsolidat#220 R10: proves assert_allocation_role_declared can fail',
     'step_down', '', now());
