# Semantic Layer and Read Path

Konsolidat has **one read path**: the konsol app (`konsol.api.epm_*` and the
report endpoints) queries the ClickHouse gold models directly through
`konsol/clickhouse.py`. The `K.` worksheet functions, the Desk reports and the
REST API all use it, so auth, entity-level permissions and write-back live in
one place.

The **semantic layer is the Dataset / Measure registry in konsol**: each site
declares its dimensions, measures and datasets there, konsol writes them into
`dbt_project.yml` vars (`cube_type` is the type / aggregation of a dimension or
measure and is read by six konsol modules; the name is historical), and dbt
builds the gold models from them. Measure logic lives in dbt, not in a client.

## Cube.js was removed (7 Nov 2026)

Until 7 Nov 2026 this page described two read paths, with Cube.js as a "core
semantic layer" that would scale reads to 50–500 users. That was a conclusion
written on 16 Sep 2026 with no owner. konsol#232, ratified by Deepak Pai on
7 Nov 2026, decided that konsol does **not** wire Cube into the read path, and
konsolidat#283 removed it from the stack rather than leave it deployed and
idle. Measured before removal: nothing in konsol called it, the Caddyfile
proxied a `konsol.cube_proxy` endpoint that never existed, and the container
used 100 MiB RSS at 0% CPU on every deploy.

Rejected: keep Cube deployed but idle; leave the question open.

## Reopen conditions (kept on konsol#232)

- a measured query near a second after the read-path work in konsol#231;
- a BI client that needs a semantic layer;
- concurrency, rather than latency, becoming the limit.

If the BI case arrives, the Dataset / Measure registry is the semantic layer
and ClickHouse views over gold are the first answer, not Cube.

## Quick decision guide

- Building a **formula, report or write-back** feature → `konsol.api`.
- Adding a **metric** → declare it in the Measure registry; dbt builds it into
  gold; konsol reads it. One definition, one path.
- Ad-hoc ODBC from Excel → ClickHouse's own PostgreSQL wire port (15432,
  loopback by default), on the internal network only.
