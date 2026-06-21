# Excel add-in — moved

**Source of truth is now the konsol Frappe app**, not this folder.

| What | Where |
|------|--------|
| Pane, `functions.js`, manifest | [`grynn-in/konsol`](https://github.com/grynn-in/konsol) → `konsol/public/excel-addin/` |
| Report API (`build_cell_map`) | same repo → `konsol/report_compiler.py`, `konsol/api.py` |
| Deploy | `konsol_cli/scripts/deploy-excel-full.sh` |
| Docs | `konsol/docs/excel-addin.md` |

Edit files in the **konsol** repo clone (e.g. `konsolidat/repo/docker/frappe/konsol/`).
This directory is kept only as a pointer for old links.