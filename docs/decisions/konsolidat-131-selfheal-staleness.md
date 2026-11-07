---
title: "Decision: Asset self-heal staleness guard (konsolidat #131)"
sidebar_label: "#131 Asset self-heal staleness"
description: Decision brief from the 2026-07-01 triage on guarding the Frappe asset-manifest self-heal, with its status as of 2026-11-05 (implemented).
---

# Decision: Asset self-heal staleness guard (konsolidat #131)

**Issue:** grynn-in/konsolidat#131 · **Status (2026-07-01):** fast-follow to #125

:::note Provenance
Written for the 2026-07-01 open-issue triage (konsolidat `1ccafa9`, 2 July 2026). A recommendation; it names no decider. Text below is verbatim. The section "Status as of 2026-11-05" was added when the page was ported.
:::

## Context
#125 moved the asset-manifest self-heal into the backend `web` entrypoint so a
bare `docker compose up` self-heals CSS 404s. But it's **unconditional**: every
web start copies the baked `assets.json`, evicts the Redis `assets_json` key, and
runs `bench clear-cache` (full Frappe boot) — even when nothing changed. It also
**clobbers the dev hot-patch flow** (`docker cp konsol` + `bench build` + restart)
by reverting to the older baked manifest on the next restart.

## Options
### A. Hash/mtime guard + timeout (recommended)
Compare the baked `assets.json` hash to the live one; skip the copy/evict/clear
when identical. Wrap `bench clear-cache` in `timeout 15`.
- **+** Removes per-restart cost; **fixes the hot-patch clobber** (a genuinely newer volume manifest is left alone); bounds the hang risk.
- **−** Slightly more shell logic; must pick the right "newer vs different" comparison (favor: heal only if live is missing or differs *and* baked is newer, else leave).

### B. Build-version marker
Bake a version/UUID at image build; entrypoint heals only when the marker changes
vs a stamp in the volume.
- **+** Deterministic "did the image change" signal.
- **−** Doesn't help the dev hot-patch case (hot-patch doesn't bump the marker); needs a stamp file.

### C. Leave as-is
- **−** Ongoing per-restart cost + hot-patch clobber. Non-fatal but wasteful and surprising.

## Recommendation
**A.** Hash-guard the heal (heal only when the live manifest is missing/stale
relative to baked) and add a `timeout` around `clear-cache`. This is the minimal
change that both drops the recurring cost and preserves an intentionally-newer
manifest from the dev hot-patch workflow. Add the `mkdir -p sites/assets` nit
while there.

## Consequences
- Low-risk, self-contained shell change; keep the best-effort/`|| true` contract from #125 (never wedge boot).

## Status as of 2026-11-05

**Implemented as option A, the same day.** konsolidat `166519a` (2026-07-02, "fix(deploy): staleness-guard + timeout the asset self-heal").

| Fact | Evidence |
|---|---|
| The guard lives in `docker/frappe/refresh-assets.sh`, called from `docker/frappe/entrypoint.sh` in `web` mode with `|| true`. | `entrypoint.sh:15-21` |
| It heals only when the live manifest is missing, or differs from the baked one and the baked one is newer (`cmp -s` plus `-nt`); a newer live manifest from an in-container `bench build` is left alone. `mkdir -p sites/assets` is there. | `refresh-assets.sh:14-40` |
| The script header cites konsolidat#131. | `refresh-assets.sh:14` |

Whether the GitHub issue is closed was not checked from this machine.
