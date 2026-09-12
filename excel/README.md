# Excel sample workbooks

Sample workbooks for the konsol Excel add-in. The add-in's worksheet functions
(`=K.EPM()`, `=K.EPM_BUDGET()`, `=K.EPMSAVE()` and the rest) are documented in the
[Excel Formulas Guide](../docs/user-guide/excel-formulas-guide.md); install the add-in
as described in the [Excel Task Pane Guide](../docs/user-guide/excel-taskpane-guide.md).

| Workbook | What it is |
|----------|------------|
| `Open_EPM_Template.xlsx` | Blank report template |
| `Open_EPM_PnL.xlsx` | P&L report built with EPM formulas |
| `Budget_Forecast_2024.xlsx` | Budget and forecast layout |

**`Open_EPM_PnL.xlsx` still uses the retired VBA function `=EPM()`.** The VBA module
was removed, so those cells show `#NAME?` until the workbook is rebuilt in Excel with
`=K.EPM()`. The arguments are the same, in the same order: replace `EPM(` with `K.EPM(`.
