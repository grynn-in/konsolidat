# Current Tasks — 2026-06-08

## Completed This Session
- [x] Rebranded Open EPM → Konsolidat across all 44 docs files, mkdocs.yml, CSS
- [x] Landing page: 1-col scenario cards, hid left nav for centered layout
- [x] Landing page: EPM() only (removed EPM_BUDGET/EPM_VARIANCE/EPMSAVE from cards)
- [x] Cost comparison: removed Planful/Prophix, kept Tagetik/OneStream/Anaplan
- [x] Added comparison chart + security section to landing page
- [x] Added Excel-first manifesto pitch
- [x] Made grynn-in/konsolidat repo public for GitHub Pages
- [x] Nav tab renamed: About → Why Konsolidat?
- [x] Merged fix/fiscal-calendar-fanout to main (PR #5)
- [x] Fixed GitHub Pages deployment (legacy → workflow build_type)
- [x] EPMSAVE() immediate write-back + budget_cell_save API
- [x] scenario_id filter on EPM()/epm_value/epm_batch
- [x] 166 TDD tests passing

## Brand
- Product name: **Konsolidat** (not Open EPM)
- Tagline: **"Excellent analysis thrives on Excel"**
- Repos: grynn-in/konsolidat (public), grynn-in/konsol (Frappe app)

## Blocked
- [ ] Office.js Task Pane sideloading — admin-managed policy

## Next Steps
- [ ] Wire Cube.js into konsol API (optional, future step)
- [ ] Office.js Task Pane — once IT enables sideloading
- [ ] Live ClickHouse integration test (CH sync on Budget Input approval)
- [ ] dbt build with Frappe-managed config (Dimension/Measure doctypes → dbt_project.yml)

## Key Facts
- Frappe: port 8069, site epm.local, bare metal /home/pd/frappe-bench
- ClickHouse pw: open_epm_dev | Admin: Administrator/admin123
- Fiscal periods are integers 1-12, not PER1/PER2 strings
- Expected load: **50-100 simultaneous Excel users**
