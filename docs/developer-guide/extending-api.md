# Extending the API

How to add new endpoints to the Frappe/Konsol API layer.

## Architecture

The API lives in `konsol/api.py` within the Frappe app. It uses Frappe's `@frappe.whitelist()` decorator to expose Python functions as HTTP endpoints.

```
Excel VBA → HTTP POST → Frappe (Konsol) → ClickHouse SQL → JSON response
```

## Frappe @whitelist Pattern

### Basic Endpoint

```python
import frappe

@frappe.whitelist()
def my_endpoint(param1, param2="default"):
    """Docstring shown in API docs."""
    # Frappe handles auth — only logged-in users can call this
    return {"result": param1}
```

Accessible at: `GET /api/method/konsol.api.my_endpoint?param1=value`

### Guest Endpoint

```python
@frappe.whitelist(allow_guest=True)
def public_endpoint():
    return {"status": "ok"}
```

### POST-Only Endpoint

```python
@frappe.whitelist(methods=["POST"])
def submit_data():
    data = frappe.request.get_data(as_text=True)
    import json
    payload = json.loads(data)
    # process payload
    return {"received": len(payload)}
```

## ClickHouse Query Pattern

The existing API uses a direct HTTP connection to ClickHouse with parameterized queries.

### Reading ClickHouse Settings

```python
def _get_clickhouse_settings():
    settings = frappe.get_single("EPM Settings")
    return {
        "host": settings.clickhouse_host or "localhost",
        "port": settings.clickhouse_port or "8123",
        "user": settings.clickhouse_user or "default",
        "password": settings.get_password("clickhouse_password") or "",
    }
```

### Executing a Query

```python
import requests

def _clickhouse_query(sql, params, ch_settings):
    url = f"http://{ch_settings['host']}:{ch_settings['port']}/"
    query_params = {
        "query": sql,
        "user": ch_settings["user"],
        "password": ch_settings["password"],
    }
    query_params.update(params)
    response = requests.get(url, params=query_params, timeout=30)
    response.raise_for_status()
    return response.text.strip()
```

### Parameterized Queries (Security)

Always use ClickHouse's parameterized query format to prevent SQL injection:

```python
sql = """
    SELECT data_area_id, sum(period_net_amount) as total
    FROM epm_gold.gold_trial_balance
    WHERE data_area_id = {entity:String}
      AND fiscal_year = {year:Int32}
    GROUP BY data_area_id
"""
params = {"param_entity": "USMF", "param_year": "2024"}
result = _clickhouse_query(sql, params, ch_settings)
```

Parameter format: `{name:Type}` in SQL, `param_name=value` in query params.

Supported types: `String`, `Int32`, `UInt16`, `Float64`, etc.

### Measure Safety

For column names from user input, use assertion validation:

```python
import re
assert re.match(r'^[a-z_]+$', measure), f"Invalid measure name: {measure}"
```

## Adding a New Scenario

To make a new Gold model queryable through `=EPM()`:

### 1. Add to SCENARIO_TABLES

```python
SCENARIO_TABLES = {
    "actuals": "epm_gold.gold_trial_balance",
    "budget": "epm_gold.gold_spread_budget",
    "variance": "epm_gold.gold_variance_analysis",
    "forecast": "epm_gold.gold_forecast_model",    # NEW
}
```

### 2. Add Allowed Measures

```python
ALLOWED_MEASURES = {
    "actuals": {"period_debit", "period_credit", "period_net_amount", ...},
    "budget": {"period_amount", "annual_amount"},
    "variance": {"actual_amount", "budget_amount", "variance_abs", ...},
    "forecast": {"forecast_amount", "confidence"},   # NEW
}
```

### 3. Test

```bash
curl "http://localhost:8069/api/method/konsol.api.epm_value?\
entity=USMF&year=2025&period=5&account=401100&\
measure=forecast_amount&scenario=forecast" \
  -b cookies.txt
```

## Adding a Standalone Endpoint

For endpoints that don't follow the EPM value pattern:

```python
@frappe.whitelist()
def get_entities():
    """Return all legal entities."""
    ch = _get_clickhouse_settings()
    sql = "SELECT DISTINCT data_area_id, entity_name FROM epm_gold.gold_trial_balance ORDER BY data_area_id"
    result = _clickhouse_query(sql, {}, ch)
    entities = []
    for line in result.split('\n'):
        if line.strip():
            parts = line.split('\t')
            entities.append({"id": parts[0], "name": parts[1] if len(parts) > 1 else parts[0]})
    return entities
```

## Error Handling

Use Frappe's exception types:

```python
import frappe

@frappe.whitelist()
def validated_endpoint(scenario):
    if scenario not in SCENARIO_TABLES:
        frappe.throw(
            f"Invalid scenario: {scenario}. Allowed: {', '.join(SCENARIO_TABLES.keys())}",
            frappe.ValidationError
        )
    # ... proceed
```

## Response Format

Frappe wraps return values in `{"message": <your_return_value>}`. The VBA module and other clients expect this wrapper.

```python
# In Python:
return {"value": 123.45}

# Client receives:
# {"message": {"value": 123.45}}
```

## Next Steps

- [API Reference](../api-reference/api-overview.md) — Existing endpoint documentation
- [Developer Overview](developer-overview.md) — Repo structure
- [Contributing](contributing.md) — PR process
