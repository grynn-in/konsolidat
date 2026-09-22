# PRD: deploy.sh step 5 runs on Linux

**Status:** Proposed (konsolidat #239)
**Date:** 2026-09-22
**Repos:** `konsolidat`

## Problem

`deploy.sh:395` creates the dbt log file with:

```bash
DBT_LOG="$(mktemp -t konsolidat-dbt)"
```

GNU coreutils requires a `-t` template to end in at least three `X`s. BSD/macOS
does not. So the line works on a developer's Mac and fails on every Linux host:

```
mktemp: too few X's in template 'konsolidat-dbt'
```

Step 5 of 5 is the dbt build. It has therefore never run on a server, and a
deploy leaves the warehouse at whatever it was before while the app runs new
code.

Measured 22 September 2026 on `debian:bookworm-slim`:

| command | exit |
|---|---|
| `mktemp -t konsolidat-dbt` | 1 — `too few X's in template` |
| `mktemp -t konsolidat-dbt.XXXXXX` | 0 |

## What the issue got wrong, and why it matters here

konsolidat#239 also says the deploy "still exits 0". Reproduced verbatim at top
level under `set -e` (which `deploy.sh:14` sets and never clears), the failing
assignment **exits 1**, not 0. A deploy that reaches step 5 on Linux fails
loudly; it does not report success. The exception is an invocation that pipes
the script into something — `./deploy.sh | tee log` takes the pipeline's exit
status from `tee`.

This matters because the issue's suggested fix is `set -o pipefail`, and
**pipefail must not be added.** Step 5 deliberately reads `${PIPESTATUS[0]}` so
that `docker compose ... | tee "$DBT_LOG"` reports dbt's status rather than
`tee`'s, and then classifies the failure: a compilation error aborts the deploy,
data-quality test failures on demo data are tolerated. Under `pipefail` plus
`set -e` the script would exit at the pipeline itself and that classification
would never run — the behaviour konsolidat#139 was filed to fix.

## Solution

One line. Use a template that both coreutils accept, and do not depend on `-t`:

```bash
DBT_LOG="$(mktemp "${TMPDIR:-/tmp}/konsolidat-dbt.XXXXXX")"
```

## Scope

- `deploy.sh:395`.
- A test that fails on the current line and passes on the fixed one.
- No change to the step's exit handling, its `PIPESTATUS` read, or its
  failure classification.

## Out of scope

- `set -o pipefail` anywhere in `deploy.sh` (see above).
- Auditing the other four steps for portability. Nothing else in the file calls
  `mktemp`; the test added here covers any future caller.

## Acceptance criteria

1. Every `mktemp` template in every shell script in the repo ends in at least
   three `X`s.
2. On a GNU-coreutils host, the template `deploy.sh` actually uses creates a
   file and exits 0.
3. `deploy.sh` still sets `set -e` and still does **not** set `pipefail`.
4. Step 5 still reads `${PIPESTATUS[0]}`.
5. The test runs in CI, in the `contract-tests` job, by name.
