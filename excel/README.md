# Excel sample workbooks

Sample workbooks for the konsol Excel add-in. The add-in's worksheet functions
(`=K.EPM()`, `=K.EPM_BUDGET()`, `=K.EPMSAVE()` and the rest) are documented in the
[Excel Formulas Guide](../docs/user-guide/excel-formulas-guide.md); install the add-in
as described in the [Excel Task Pane Guide](../docs/user-guide/excel-taskpane-guide.md).

| Workbook | What it is | State |
|----------|------------|-------|
| `Open_EPM_Template.xlsx` | Report template | Its instruction text still describes the retired VBA module (importing `OpenEPM.bas`, Ctrl+Shift+R); the layout itself works with the add-in |
| `Open_EPM_PnL.xlsx` | P&L report built with EPM formulas | Its formulas call the retired `=EPM()` and show `#NAME?` until rebuilt |

Both were made for the retired VBA module and need updating in Excel. For
`Open_EPM_PnL.xlsx`, replace `EPM(` with `K.EPM(`: the arguments are the same, in the
same order. The VBA-only budget upload workbook (`Budget_Forecast_2024.xlsx`) and its
generator were removed with the VBA module; budgets are written with `=K.EPMSAVE()`.
