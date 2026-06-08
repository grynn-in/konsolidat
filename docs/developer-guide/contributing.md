# Contributing

Guidelines for contributing to Konsolidat.

## Git Workflow

1. **Fork** the repository (or create a feature branch from `main`)
2. **Branch** from `main`: `git checkout -b feature/your-feature`
3. **Commit** with clear messages describing the change
4. **Push** and open a **Pull Request** against `main`
5. Request review and address feedback

### Branch Naming

```
feature/description     # New functionality
fix/description         # Bug fixes
docs/description        # Documentation only
refactor/description    # Code restructuring
```

### Commit Messages

```
feat: add gold_cash_flow_statement model
fix: correct CTA calculation for equity accounts
docs: update consolidation guide with NCI examples
refactor: extract ClickHouse query builder
test: add assert_cash_flow_nets_to_bs
```

## Code Style

### SQL (dbt Models)

- **Lowercase** keywords: `select`, `from`, `where`, `group by`
- **snake_case** for all identifiers: `data_area_id`, `period_net_amount`
- **Prefix** dimensions with `dim_`: `dim_cost_center`, `dim_department`
- Use **dimension macros** instead of hardcoding dimension columns
- Use **db_adapter macros** for ClickHouse-specific functions
- Use **CTEs** over subqueries for readability
- Add a comment at the top of each model describing its purpose

### Python (Frappe/Konsol)

- Follow **PEP 8**
- Use **type hints** for function parameters
- Validate all user input before building SQL
- Use **parameterized queries** for ClickHouse (never string interpolation)
- Raise `frappe.ValidationError` for bad input

### VBA

- `PascalCase` for public functions and macros
- `camelCase` for local variables
- `pVariableName` for module-level private variables
- Add error handling to all public functions

### Seeds (CSV)

- Use **snake_case** for column headers
- Sort rows by primary key
- No trailing commas or empty rows
- Use consistent quoting (only when values contain commas)

## Testing Requirements

### dbt Models

- Every Gold model must have at least one assertion test
- Tests should validate business logic, not just schema
- Use `0.01` tolerance for financial amount comparisons
- Name tests `assert_{what_is_being_tested}`

### API Endpoints

- Test with `curl` examples in the PR description
- Validate error responses for invalid input
- Test batch size limits

### Running the Test Suite

```bash
cd dbt_project
dbt build    # Models + tests
```

All tests must pass before merging.

## Pull Request Checklist

- [ ] Branch is based on latest `main`
- [ ] Code follows project conventions
- [ ] dbt models use dimension/measure macros where applicable
- [ ] New models documented in `_*__models.yml`
- [ ] Tests added for new functionality
- [ ] `dbt build` passes with 0 errors
- [ ] PR description includes what changed and why
- [ ] Documentation updated if user-facing behavior changed

## Repository Structure

See [Developer Overview](developer-overview.md) for the full directory layout.

## Getting Help

- Open a [GitHub Issue](https://github.com/your-org/konsolidat/issues) for bugs or feature requests
- Check existing [documentation](../index.md) before asking
- Include reproduction steps and dbt/ClickHouse version info in bug reports
