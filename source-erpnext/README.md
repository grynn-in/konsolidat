# source-erpnext

Airbyte source connector for **ERPNext** — lands the GL-entry-family doctypes
over the standard Frappe REST API into `epm_raw`, where the dbt
`stg_erpnext__*` adapter transforms them into the canonical staging interface.

## Streams

| Stream (raw table) | ERPNext DocType | Mode | Cursor |
|---|---|---|---|
| `gl_entry` | `GL Entry` | Incremental | `modified` |
| `account` | `Account` | Full refresh | — |
| `company` | `Company` | Full refresh | — |
| `currency_exchange` | `Currency Exchange` | Incremental | `modified` |
| `budget` | `Budget` (+ `Budget Account` child, flattened) | Incremental | `modified` |
| `fiscal_year` | `Fiscal Year` | Full refresh | — |

`budget` lands one row per `Budget Account` child line; because the Frappe list
endpoint omits child tables, the stream fetches each Budget document's detail to
flatten its lines.

## Authentication

Frappe uses a static token header — no OAuth exchange:

```
Authorization: token <api_key>:<api_secret>
```

Generate an API key/secret in ERPNext under **User → Settings → API Access**.
The key's user must have read access to the doctypes above.

## Config

| Field | Required | Default | Notes |
|---|---|---|---|
| `host_url` | yes | — | ERPNext base URL, e.g. `https://erp.mycompany.com` (no `/api`). |
| `api_key` | yes | — | API key (secret). |
| `api_secret` | yes | — | API secret (secret). |
| `page_size` | no | 500 | `limit_page_length` per Frappe REST page. |

## Local run

```bash
pip install -e .
source-erpnext spec
source-erpnext check --config secrets/config.json
source-erpnext discover --config secrets/config.json
source-erpnext read --config secrets/config.json --catalog integration_tests/configured_catalog.json
```

## Pagination & incremental

Paging uses `limit_start` / `limit_page_length`; a page shorter than
`page_size` ends the stream. Incremental streams add a JSON
`filters=[["modified", ">=", <state>]]` and advance the `modified` high-water
mark per record.
