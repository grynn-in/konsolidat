# PRD: a backup can be restored in the image

**Status:** Proposed (konsolidat #240)
**Date:** 2026-09-22
**Repos:** `konsolidat`

## Problem

Frappe shells out to `file(1)` to decide whether a dump is gzipped, at
`frappe/commands/site.py:234` (restore) and `:375` (partial restore):

```python
err, out = frappe.utils.execute_in_shell(f"file {sql_file_path}", check_exit_code=True)
```

`docker/frappe/Dockerfile:6-18` installs `git curl wget cron mariadb-client`,
fonts, `build-essential`, nodejs, yarn and wkhtmltopdf — **not `file`**. So
`bench restore` fails in the image:

```
/usr/bin/bash: line 1: file: command not found
frappe.exceptions.CommandFailedError: Command failed
```

Measured 22 September 2026 in the running `konsolidat_backend`:
`command -v file` → nothing; both call sites confirmed in the installed frappe.

A backup that cannot be restored is not a backup. The demo rebuild on 22
September needed `bench restore` and got this; `file` was installed **by hand
into the running container**, which the next image build discards.

## What the issue got wrong, and why the fix is still right

konsolidat#240 says this breaks `./deploy.sh restore --from <path>`, the path
`docs/admin-guide/deployment-guide.md:250` documents. It does not:
`deploy.sh:87-128` restores MariaDB by piping the dump into the `mariadb`
client, untars the Frappe files and `curl`s the ClickHouse natives. It never
invokes `bench`, and the strings `bench restore` appear nowhere in the repo's
scripts or docs.

The defect is real anyway, and it is the one an operator actually hits: the
standard Frappe recovery command, and the only way to load a `.sql.gz` produced
by `bench backup` into a site. It just is not reached through `deploy.sh`.

## Solution

Add `file` to the apt list in `docker/frappe/Dockerfile`.

## Scope

- `docker/frappe/Dockerfile`, one package in the existing `apt-get install`.
- A test that fails on the current list and passes on the fixed one.

## Out of scope

- The CI restore smoke test the issue suggests (back up a seeded site, restore
  it into a second site, assert a row count). It is the right test and it is a
  separate piece of work: this repo has no Frappe site in CI, and konsol's
  `CLAUDE.md` forbids a second site against the shared ClickHouse. Filed as
  konsolidat#241 rather than smuggled in here.
- `deploy.sh restore`'s own mechanism, which bypasses bench entirely. Worth a
  look; not this change.

## Acceptance criteria

1. `docker/frappe/Dockerfile` installs `file`.
2. On `python:3.11-slim-bookworm` — the image's own base — installing that
   package yields a working `/usr/bin/file`. Measured by hand, 22 Sep 2026:
   `file-5.44`.

**There is deliberately no automated test.** Three were written and all three
were wrong. Each read the Dockerfile to decide whether it installed a package,
and each was a parser: the first passed a Dockerfile that named `file` only in
a comment inside a `\`-continued `RUN`; the second gave false reds on
`;`-separated commands, `apt install` and version pins; the third passed
`RUN apt-get install -y curl && echo 'writing file' > /tmp/x` with the package
absent, and failed a correct Dockerfile with a blank line inside a
continuation.

A guard that can pass while the bug is present is worse than no guard — it is
the shape konsol#248 and konsolidat#227 were filed for, and konsolidat#240 is
itself an instance of it. So the guard was deleted rather than patched a fourth
time (Deepak, 22 Sep 2026).

The only honest answer to "does the image contain `file`?" is to build the
image and look, which nothing in CI does today. That is **konsolidat#244**, and
it guards something larger as well: that the image builds at all.

## Residual, stated plainly

The full image is **not** rebuilt by this change, and nothing automatic guards
the package list. What is proven is that the list asks for `file` and that the
package provides the binary on this base. The first real rebuild closes the
loop — and until it happens, the demo's `file(1)` remains a hand-install that
that rebuild will discard and then restore.
