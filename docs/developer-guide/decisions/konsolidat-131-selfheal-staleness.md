# Decision: Asset self-heal staleness guard (konsolidat #131)

**Issue:** grynn-in/konsolidat#131 · **Status:** fast-follow to #125

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
