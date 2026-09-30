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
- Auditing the other four steps for portability.
- **The other nine shell scripts in the repo.** The first attempt at this PRD
  guarded all ten by parsing shell in a unit test to find `mktemp` templates.
  Two review rounds found nine defects in that parser and none in the one-line
  fix it guarded, so it was deleted (Deepak, 22 Sep 2026) and the guard narrowed
  to the call site with a proven bug. The other nine are konsolidat#243, to be
  done with a real shell parser (shellcheck) rather than another hand-written
  one.

## Acceptance criteria

1. On a GNU-coreutils host, every `mktemp` call in `deploy.sh` exits 0 and
   creates a file **in the temporary directory** — run, not read — with
   `TMPDIR` set and with it unset. Where the file landed, not merely that it
   exists: as root, `mktemp "${TMPDIR}/x.XXXXXX"` with `TMPDIR` unset creates
   `/x.XXXXXX` quite happily, so an existence check passes the very bug this
   guards. (`mktemp -u` prints a name and creates nothing, which is fair for a
   path `tee` will create; that call is checked but not failed for absence.)
2. A `mktemp` call in a shape the guard cannot run fails the guard by name,
   rather than being skipped. That includes a capture carrying a second command
   (`$(mktemp -d && chmod …)`) and a nested `$( )`: the guard refuses them and
   says why, rather than splitting shell it cannot parse.
3. `deploy.sh` still sets `set -e` and still does **not** set `pipefail`.
4. Step 5 still reads `${PIPESTATUS[0]}`.
5. The test runs in CI by name, in the `deploy guards` workflow. It is not in
   `dbt-checks.yml`: that workflow's `paths` is workflow-level, so listing
   `deploy.sh` there dragged a full warehouse build onto every deploy edit.
