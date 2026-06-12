# `=EPM()` Client Protocol

The `=EPM()` worksheet functions are implemented by **two independent clients**
that talk to the same Frappe API:

- **Office.js add-in** — `excel-addin/src/taskpane.js` (also vendored into the
  konsol app at `konsol/public/excel-addin/`)
- **VBA module** — `excel/OpenEPM.bas`

Because the protocol is implemented twice, this document is the **single source
of truth** for the wire contract. Both clients must conform to it; the parity
test (`tests/test_epm_client_parity.py`) enforces the key invariants.

## Endpoints

| Purpose | Method | Path |
|---|---|---|
| Batch value read | `POST` | `/api/method/konsol.api.epm_batch` |
| Single value read | `GET`/`POST` | `/api/method/konsol.api.epm_value` |
| Budget write-back (batch) | `POST` | `/api/method/konsol.api.budget_save_batch` |
| Health | `GET` | `/api/method/konsol.api.health` |

## `epm_batch` request

The request body is a **bare JSON array** (not an object wrapper). Each element:

```json
{
  "entity": "USMF",
  "year": 2024,
  "period": 1,
  "account": "110100",
  "measure": "period_net_amount",
  "scenario": "actuals",
  "scenario_id": "",
  "cost_center": "",
  "department": "",
  "dimensions": { "dim_cost_center": "001" }
}
```

Canonical keys: **`entity`, `year`, `period`, `account`, `measure`, `scenario`**
(plus optional `scenario_id`, `cost_center`, `department`, `dimensions`).

- `period` accepts `1`–`12`, or a range token `Q1`–`Q4`, `H1`/`H2`, `FY`.
- **Do not** use `fiscal_year` / `fiscal_period` for `epm_batch` — those are the
  doctype field names, not the API keys.
- Maximum **2000** items per request (`MAX_BATCH_SIZE` in `konsol/api.py`).
  Clients must chunk larger requests.

## `epm_batch` response

```json
{ "values": [123.45, 0, null], "errors": [null, null, "..."] }
```

- `values` is an array of **numbers** (or `null`), positionally matching the
  request array.
- `errors` is present only if at least one row failed; same positional indexing.
- Over Frappe, the whole object is wrapped under `message`, so clients read
  `response.message.values`.

## Versioning

When changing the contract (keys, batch size, response shape), update **this
document**, **both clients**, and the parity test in the same change.
