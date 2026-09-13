# Trial Balance Upload Guide

Entities that no ERP connector feeds send their trial balance to konsol as a file. There are two ways in:

| | Single submission | Bulk upload |
|---|---|---|
| Where | Desk: **Trial Balance Submission** | konsol-exec: **Upload trial balances** (`/konsol-exec/uploads`) |
| One file holds | One entity, one period | Many entities and periods |
| File type | CSV | CSV, or the first sheet of an Excel `.xlsx` workbook |
| Who | Entity Accountant (own entities), Close Lead, System Manager | Close Lead (EPM Admin), System Manager |

A bulk upload is split into one ordinary Trial Balance Submission per entity and period, so the rules below apply to both, except where a rule says otherwise.

## The Rules Every Trial Balance Obeys

- **Debits equal credits**, within 0.01.
- **Amounts are in the entity's own accounting currency**, rounded to cents. Consolidation translates them.
- **Debit and credit are both positive.** Post a negative value to the opposite column.
- **One row per account** (and per partner, for intercompany rows).
- **Every account is in the group chart.** If the warehouse cannot be reached, the file is refused rather than accepted unchecked.
- **Periods 1 to 12.** Opening (OPN) and closing (CLS) periods are not uploaded as trial balances.
- **The period is open.** A Closed or Locked period refuses it.
- **One live submission per entity and period.** To correct one, cancel or amend it first, then submit the new one.
- **You may access the entity.** A bulk upload also refuses a group node; in Desk, choose an entity that is not a group.

## Single Submission

1. In Desk, open **Trial Balance Submission** → New. An Entity Accountant can also start from the month view: the row **Upload trial balance** opens a new submission with the entity and period filled in.
2. Choose the **Entity**, **Fiscal Year** and **Fiscal Period**.
3. Attach the file under **Trial Balance CSV**. Its header is:

    ```
    main_account,debit,credit[,description][,partner_data_area_id]
    ```

4. **Save.** konsol validates the file and fills in **Rows**, **Total Debit**, **Total Credit** and **Validation Status** (Valid). Row problems stop the save with "Trial balance failed validation:" followed by every one found. An unreadable file, a closed period, an entity you cannot access or an existing submission is refused with its own message. An intercompany row without a partner does not stop the save: the warning is shown and kept in **Validation Message**.
5. **Submit.** The rows land in the warehouse and a consolidation build is requested.

Submissions are named `TBS-<entity>-<year>-P<period>-<n>`, for example `TBS-DE01-2026-P9-001`.

## Bulk Upload

### The File

A header row is required. Column names are not case-sensitive, and spaces or hyphens in them count as underscores.

| Column | Also accepted as | Required | Content |
|---|---|---|---|
| `data_area_id` | `entity`, `entity_id`, `company` | Yes | Entity code |
| `fiscal_year` | `year` | Yes | Whole number, e.g. `2026` |
| `fiscal_period` | `period` | Yes | `1` to `12` |
| `main_account` | `account`, `account_id` | Yes | Group chart account |
| `debit` | | Yes | Positive amount or blank |
| `credit` | | Yes | Positive amount or blank |
| `description` | | No | Free text |
| `partner_data_area_id` | `partner`, `partner_entity`, `partner_id`, `counterparty` | No | The other group entity an intercompany row is held with |

- Save CSV files as UTF-8. Excel's **CSV UTF-8** format (which starts with a byte-order mark) is read correctly.
- For a workbook, konsol reads the **first sheet**, whichever sheet was selected when it was saved.
- An account typed as a number in Excel (`110100.0`) is read as `110100`.

**The partner column.** A row on an [Intercompany Account](intercompany-guide.md) needs the partner entity to be eliminated. A partner must be an existing entity that is not a group, and never the row's own entity. A blank partner is allowed: the row loads, and is reported with a warning, because it will not be eliminated.

### Worked Example

`tb_2026_09.csv`, September 2026 for three entities:

```
entity,year,period,account,debit,credit,description,partner
DE01,2026,9,110100,25000,0,Cash,
DE01,2026,9,130100,4000,0,Receivable from AT01,AT01
DE01,2026,9,401100,0,29000,Revenue,
AT01,2026,9,110100,8000,0,Cash,
AT01,2026,9,210100,0,4000,Payable to DE01,DE01
AT01,2026,9,401100,0,4000,Revenue,
US01,2026,9,110100,12000,0,Cash,
US01,2026,9,401100,0,11500,Revenue,
```

DE01 balances at 29,000, AT01 at 8,000. US01 does not: its debits are 12,000 and its credits 11,500.

### Check, Then Load

1. Open **Upload trial balances** from the navigator or the month view, and choose the file.
2. konsol checks every entity-period in it. **Nothing loads yet.** The page lists each one as **Ready** or **Problem**:

    | Entity | Period | Rows | Debit | Credit | Status | Detail |
    |---|---|---|---|---|---|---|
    | DE01 | FY2026 P09 | 3 | 29,000.00 | 29,000.00 | Ready | |
    | AT01 | FY2026 P09 | 3 | 8,000.00 | 8,000.00 | Ready | |
    | US01 | FY2026 P09 | 2 | 12,000.00 | 11,500.00 | Problem | Debits (12,000.00) do not equal credits (11,500.00); difference 500.00 exceeds the 0.01 tolerance |

3. Press **Load 2 trial balances, skip 1** to load only the ready ones, or fix the file and choose it again. With no problems, the button reads **Load 3 trial balances**.
4. The load runs in the background. A progress bar counts entity-periods loaded, and each loaded row links to its Trial Balance Submission. The consolidation build is requested automatically.

Loading checks the file again first, because a period may have closed or someone may have submitted in the meantime. If new problems appeared and you did not choose to skip problems, nothing loads and the page says so: "1 of 3 entity-periods have problems now. Load only the 2 that are ready, or fix the file."

### What the Check Refuses

For one entity-period (the rest of the file can still load):

| Problem | Message |
|---|---|
| Unknown entity, or one you cannot access | "Entity CH01 does not exist, or you have no access to it" |
| A group node | "EUROPE is a group; trial balances belong to the entities under it" |
| Period outside 1–12 | "Fiscal period must be 1 to 12" |
| Closed or locked period | "FY2026 P08 is closed" |
| Already submitted | "TBS-DE01-2026-P9-001 is already submitted for this entity and period; cancel or amend it first" |
| Unbalanced | "Debits (12,000.00) do not equal credits (11,500.00); difference 500.00 exceeds the 0.01 tolerance" |
| Accounts not in the group chart | "Account(s) not in the group chart: 999999" |
| An account twice | "Duplicate account rows: 110100 — one row per account and partner; merge them before submitting" |
| Negative amounts | "Negative amounts on: 401100 — post the value to the opposite column instead of using a sign" |
| Unknown partner | "Unknown partner entity: at01 (did you mean AT01?) — a partner must be an existing entity that is not a group" |
| Partner is the entity itself | "Partner is the entity itself (DE01) on: 130100 — a partner is the other group entity; leave it blank for a third party" |

A warning, which does not stop the load: "1 intercompany row without a partner (account 130100). It loads, but is never eliminated: consolidation lists them as unmatched. Add partner_data_area_id to eliminate them."

For the whole file, reported together (up to 20 lines) so you can fix it in one pass:

| Problem | Message |
|---|---|
| A required column is missing | "Missing column(s) credit on line 1. The header must be data_area_id, fiscal_year, fiscal_period, main_account, debit, credit[, description][, partner_data_area_id]" |
| Not a number | "Line 4: debit must be a number (got 'n/a')" |
| Blank entity or account | "Line 7: data_area_id is blank" |
| Year or period not a whole number | "Line 5: fiscal_period must be a whole number (got 'Sep')" |
| Extra cells | "Line 9: more cells than the header has columns" |
| Two partner columns | "Two partner columns on line 1: keep one" |
| Empty file | "The file is empty: expected a header row" / "The file has a header but no data rows" |
| Wrong file type | "Upload a .csv or .xlsx file." |

### Stopped or Partly Loaded Uploads

Each entity-period is committed on its own as soon as it loads, and progress is saved after every one. A load that stops part-way (the worker restarted, or it reached its time limit of about 50 minutes: "Stopped at the time limit; resume the load to finish it.") keeps what it loaded. Open the upload again and press **Resume: load the remaining N**.

A resume never loads anything twice: entity-periods this upload already loaded are recognised and carried forward. If one of them has since been cancelled, it is shown as a problem rather than loaded again: "Loaded earlier as TBS-DE01-2026-P9-001, which has since been cancelled. Upload the file again if it should be loaded anew."

## The Audit Trail

Every bulk upload is kept as a **Trial Balance Upload** record in Desk (`TBU-00001`, …). **Recent uploads** on the upload page links to them.

| Field | Content |
|---|---|
| File | The uploaded file, as received |
| Status | Draft, Checked, Loading, Loaded, Partly Loaded or Failed |
| Entity-periods, Ready, Rows | What the check found |
| Loaded, Failed | What the load did |
| Problem with the file | Why the file could not be read, or why a load stopped |
| Report | Every entity-period with its checks and the submission it created |

Each entity-period's submission carries its own generated file, named `<upload>-<entity>-<year>-P<period>.csv` (for example `TBU-00001-DE01-2026-P09.csv`), so you can trace any submission back to its upload.

Only the Close Lead (EPM Admin) and System Managers can use the bulk upload. Anyone else is told "Loading trial balances in bulk needs the Close Lead role (EPM Admin)." An upload holds every entity's figures, so a user limited to some entities sees only the uploads they made, and can open another's upload only if they may see every entity in it.

## Next Steps

- [Month-End Close Guide](month-close-guide.md): where the Trial balances stage shows what is in and what is missing
- [Intercompany Guide](intercompany-guide.md): Intercompany Accounts and how partner rows are eliminated
- [Consolidation Guide](consolidation-guide.md): what happens to the figures after they load
