' ============================================================
' Open EPM — Excel Add-in (SmartView-style batch retrieval)
' ============================================================
'
' How it works:
'   1. Write =EPM(...) formulas in cells — they return cached values or 0
'   2. Click Refresh (Ctrl+Shift+R) or run EPM_Refresh
'   3. VBA scans the sheet, collects ALL EPM cells, sends ONE batch
'      request to the server, and populates every cell at once
'
' Functions:
'   =EPM(entity, year, period, account)
'   =EPM(entity, year, period, account, measure, scenario, cost_center, dept, scenario_id)
'   =EPM_BUDGET(entity, year, period, account)
'   =EPM_VARIANCE(entity, year, period, account)
'
' Macros:
'   EPM_Login             Log in to Frappe (prompted automatically on refresh)
'   EPM_Refresh           Refresh active sheet   (Ctrl+Shift+R)
'   EPM_RefreshAll        Refresh all sheets
'   EPM_ClearCache        Clear cached values
'   EPM_SetServer         Change API server URL
'   EPM_ToggleLog         Toggle logging to _EPM_Log sheet
'
' ============================================================

Option Explicit

' ── Configuration ───────────────────────────────────────────
Private Const DEFAULT_API_URL As String = "http://localhost:8069"
Private pApiUrl As String
Private pCache As Object  ' Scripting.Dictionary
Private pLoggedIn As Boolean
Private pSessionCookie As String
Private Const LOG_SHEET_NAME As String = "_EPM_Log"
Private pLoggingEnabled As Boolean

Public Property Get API_BASE_URL() As String
    If pApiUrl = "" Then
        On Error Resume Next
        pApiUrl = ActiveWorkbook.CustomDocumentProperties("EPM_API_URL").Value
        On Error GoTo 0
        If pApiUrl = "" Then pApiUrl = DEFAULT_API_URL
    End If
    API_BASE_URL = pApiUrl
End Property

' ── Session cookie ──────────────────────────────────────────

Public Sub EPM_Login()
    Dim usr As String, pwd As String
    usr = InputBox("Frappe email / username:", "Open EPM Login")
    If usr = "" Then Exit Sub
    pwd = InputBox("Password:", "Open EPM Login")
    If pwd = "" Then Exit Sub

    Dim http As Object
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    Dim url As String
    url = API_BASE_URL & "/api/method/login"

    On Error GoTo LoginFail
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    http.send "{""usr"":""" & JsonEscape(usr) & """,""pwd"":""" & JsonEscape(pwd) & """}"

    If http.Status <> 200 Then
        MsgBox "Login failed (HTTP " & http.Status & "): " & http.responseText, vbExclamation, "Open EPM"
        Exit Sub
    End If

    ' Extract session cookies from Set-Cookie headers
    Dim headers As String
    headers = http.getAllResponseHeaders()
    pSessionCookie = ExtractCookies(headers)
    pLoggedIn = True

    LogMsg "INFO", "Logged in as " & usr
    MsgBox "Logged in as " & usr & ". Press Ctrl+Shift+R to refresh.", vbInformation, "Open EPM"
    Exit Sub

LoginFail:
    LogMsg "ERROR", "Login failed: " & Err.Description
    MsgBox "Cannot connect to " & url & vbCrLf & Err.Description, vbExclamation, "Open EPM"
End Sub

Private Function ExtractCookies(headers As String) As String
    ' Parse Set-Cookie headers and build a Cookie string
    Dim lines() As String
    Dim i As Long
    Dim cookies As String
    lines = Split(headers, vbCrLf)
    For i = 0 To UBound(lines)
        If LCase(Left(lines(i), 11)) = "set-cookie:" Then
            Dim val As String
            val = Trim(Mid(lines(i), 12))
            ' Take only the name=value part (before first ;)
            Dim sc As Long
            sc = InStr(val, ";")
            If sc > 0 Then val = Left(val, sc - 1)
            If cookies <> "" Then cookies = cookies & "; "
            cookies = cookies & val
        End If
    Next i
    ExtractCookies = cookies
End Function

' ── Cache management ─────────────────────────────────────────

Private Sub EnsureCache()
    If pCache Is Nothing Then
        Set pCache = CreateObject("Scripting.Dictionary")
    End If
End Sub

Public Sub EPM_ClearCache()
    Set pCache = Nothing
    MsgBox "Cache cleared. Press Ctrl+Shift+R to refresh.", vbInformation, "Open EPM"
End Sub

' ── EPM functions (return cached value or 0) ────────────────

Public Function EPM( _
    entity As String, _
    fiscal_year As Variant, _
    fiscal_period As Variant, _
    account As String, _
    Optional measure As String = "period_net_amount", _
    Optional scenario As String = "actuals", _
    Optional cost_center As String = "", _
    Optional department As String = "", _
    Optional scenario_id As String = "" _
) As Variant
    Dim Key As String
    Key = BuildKey(CStr(entity), CLng(fiscal_year), CStr(fiscal_period), CStr(account), _
                   measure, scenario, cost_center, department, scenario_id)

    If pCache Is Nothing Then
        EPM = 0
    ElseIf pCache.Exists(Key) Then
        EPM = pCache(Key)
    Else
        EPM = 0
    End If
End Function

Public Function EPM_BUDGET( _
    entity As String, fiscal_year As Variant, fiscal_period As Variant, _
    account As String, _
    Optional cost_center As String = "", Optional department As String = "", _
    Optional scenario_id As String = "" _
) As Variant
    EPM_BUDGET = EPM(entity, fiscal_year, fiscal_period, account, _
                     "period_amount", "budget", cost_center, department, scenario_id)
End Function

Public Function EPM_VARIANCE( _
    entity As String, fiscal_year As Variant, fiscal_period As Variant, _
    account As String, _
    Optional cost_center As String = "", Optional department As String = "", _
    Optional scenario_id As String = "" _
) As Variant
    EPM_VARIANCE = EPM(entity, fiscal_year, fiscal_period, account, _
                       "variance_abs", "variance", cost_center, department, scenario_id)
End Function

Public Function EPM_DEBIT( _
    entity As String, fiscal_year As Variant, fiscal_period As Variant, _
    account As String, _
    Optional cost_center As String = "", Optional department As String = "" _
) As Variant
    EPM_DEBIT = EPM(entity, fiscal_year, fiscal_period, account, _
                    "period_debit", "actuals", cost_center, department)
End Function

Public Function EPM_CREDIT( _
    entity As String, fiscal_year As Variant, fiscal_period As Variant, _
    account As String, _
    Optional cost_center As String = "", Optional department As String = "" _
) As Variant
    EPM_CREDIT = EPM(entity, fiscal_year, fiscal_period, account, _
                     "period_credit", "actuals", cost_center, department)
End Function

' ── REFRESH: scan sheet, batch fetch, populate ──────────────

Public Sub EPM_Refresh()
    Dim n As Long
    n = RefreshSheet(ActiveSheet)
    Application.StatusBar = False
End Sub

Public Sub EPM_RefreshAll()
    Dim ws As Worksheet
    Dim total As Long
    Dim current As Long
    Dim totalCells As Long

    total = ActiveWorkbook.Worksheets.Count
    current = 0

    For Each ws In ActiveWorkbook.Worksheets
        current = current + 1
        Application.StatusBar = "Open EPM: Sheet " & current & "/" & total & " — " & ws.Name
        Dim n As Long
        n = RefreshSheet(ws)
        totalCells = totalCells + n
    Next ws

    Application.StatusBar = False
    MsgBox "Done — " & totalCells & " cells refreshed across " & total & " sheets.", _
           vbInformation, "Open EPM"
End Sub

Private Function RefreshSheet(ws As Worksheet) As Long
    Dim cell As Range
    Dim epmRange As Range  ' Union of all EPM cells for single recalc
    Dim requests As New Collection
    Dim keys As New Collection
    Dim usedRange As Range
    Dim r As Long
    Dim c As Long
    Dim f As String
    Dim args As Object
    Dim i As Long
    Dim prevCalc As Long

    EnsureCache

    Application.StatusBar = "Open EPM: Scanning " & ws.Name & "..."
    DoEvents

    Set usedRange = ws.UsedRange
    If usedRange Is Nothing Then Exit Function

    ' Scan all formula cells for EPM functions
    For r = 1 To usedRange.Rows.Count
        For c = 1 To usedRange.Columns.Count
            Set cell = usedRange.Cells(r, c)
            If cell.HasFormula Then
                f = UCase(cell.Formula)
                If InStr(f, "EPM(") > 0 Or InStr(f, "EPM_BUDGET(") > 0 Or _
                   InStr(f, "EPM_VARIANCE(") > 0 Or InStr(f, "EPM_DEBIT(") > 0 Or _
                   InStr(f, "EPM_CREDIT(") > 0 Then

                    Set args = Nothing
                    Set args = ResolveEpmArgs(cell)
                    If Not args Is Nothing Then
                        ' Build union range for single recalc later
                        If epmRange Is Nothing Then
                            Set epmRange = cell
                        Else
                            Set epmRange = Union(epmRange, cell)
                        End If
                        requests.Add args
                        keys.Add args("key")
                    End If
                End If
            End If
        Next c
    Next r

    If requests.Count = 0 Then
        LogMsg "INFO", ws.Name & ": no EPM formulas found"
        Exit Function
    End If

    LogMsg "INFO", ws.Name & ": found " & requests.Count & " EPM formulas"
    Application.StatusBar = "Open EPM: Fetching " & requests.Count & " values from " & ws.Name & "..."
    DoEvents

    ' Build JSON batch request
    Dim json As String
    Dim req As Object
    json = "["
    For i = 1 To requests.Count
        Set req = requests(i)
        If i > 1 Then json = json & ","
        json = json & "{"
        json = json & """entity"":""" & JsonEscape(CStr(req("entity"))) & """"
        json = json & ",""year"":" & req("year")
        json = json & ",""period"":""" & JsonEscape(CStr(req("period"))) & """"
        json = json & ",""account"":""" & JsonEscape(CStr(req("account"))) & """"
        json = json & ",""measure"":""" & JsonEscape(CStr(req("measure"))) & """"
        json = json & ",""scenario"":""" & JsonEscape(CStr(req("scenario"))) & """"
        If req("cost_center") <> "" Then
            json = json & ",""cost_center"":""" & JsonEscape(CStr(req("cost_center"))) & """"
        End If
        If req("department") <> "" Then
            json = json & ",""department"":""" & JsonEscape(CStr(req("department"))) & """"
        End If
        If req("scenario_id") <> "" Then
            json = json & ",""scenario_id"":""" & JsonEscape(CStr(req("scenario_id"))) & """"
        End If
        json = json & "}"
    Next i
    json = json & "]"

    ' Ensure logged in
    If Not pLoggedIn Or pSessionCookie = "" Then
        EPM_Login
        If Not pLoggedIn Then Exit Function
    End If

    ' POST batch request
    Dim http As Object
    Dim url As String
    url = API_BASE_URL & "/api/method/konsol.api.epm_batch"

    On Error GoTo FetchError
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    http.setTimeouts 5000, 10000, 30000, 60000
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    http.setRequestHeader "Cookie", pSessionCookie
    http.send json

    ' If unauthorized, try login and retry
    If http.Status = 401 Or http.Status = 403 Then
        pLoggedIn = False
        EPM_Login
        If Not pLoggedIn Then Exit Function
        Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
        http.setTimeouts 5000, 10000, 30000, 60000
        http.Open "POST", url, False
        http.setRequestHeader "Content-Type", "application/json"
        http.setRequestHeader "Cookie", pSessionCookie
        http.send json
    End If

    If http.Status <> 200 Then
        LogMsg "ERROR", ws.Name & ": server returned HTTP " & http.Status
        MsgBox "EPM server returned error " & http.Status & ": " & http.responseText, _
               vbExclamation, "Open EPM"
        Exit Function
    End If

    LogMsg "INFO", ws.Name & ": received " & Len(http.responseText) & " bytes"

    ' Parse response: {"message": {"values": [1.0, 2.0, ...]}}
    Dim response As String
    response = http.responseText
    Set http = Nothing

    Dim parsedValues() As Double
    parsedValues = ParseValuesArray(response, requests.Count)

    ' Populate cache
    Application.StatusBar = "Open EPM: " & ws.Name & " — populating " & requests.Count & " cells..."
    DoEvents
    Dim cacheKey As String
    For i = 1 To requests.Count
        cacheKey = keys(i)
        If pCache.Exists(cacheKey) Then
            pCache(cacheKey) = parsedValues(i - 1)
        Else
            pCache.Add cacheKey, parsedValues(i - 1)
        End If
    Next i

    ' Recalculate all EPM cells in one shot (Union range)
    prevCalc = Application.Calculation
    Application.ScreenUpdating = False
    Application.EnableEvents = False
    Application.Calculation = xlCalculationManual
    If Not epmRange Is Nothing Then epmRange.Calculate
    Application.Calculation = prevCalc
    Application.EnableEvents = True
    Application.ScreenUpdating = True

    LogMsg "INFO", ws.Name & ": refreshed " & requests.Count & " cells"
    RefreshSheet = requests.Count
    Exit Function

FetchError:
    ' Restore Application state on error
    Application.StatusBar = False
    Application.ScreenUpdating = True
    Application.EnableEvents = True
    On Error Resume Next
    Application.Calculation = xlCalculationAutomatic
    On Error GoTo 0
    LogMsg "ERROR", ws.Name & ": " & Err.Description
    MsgBox "Cannot connect to EPM server at " & url & vbCrLf & _
           "Error: " & Err.Description, vbExclamation, "Open EPM"
End Function

' ── Parse the values array from JSON response ────────────────

Private Function ParseValuesArray(response As String, expectedCount As Long) As Double()
    Dim result() As Double
    ReDim result(0 To expectedCount - 1)

    Dim arrStart As Long
    Dim arrEnd As Long
    arrStart = InStr(response, "[")
    arrEnd = InStrRev(response, "]")

    If arrStart = 0 Or arrEnd <= arrStart Then
        ParseValuesArray = result
        Exit Function
    End If

    ' Walk the array character by character to handle nulls properly
    Dim content As String
    content = Mid(response, arrStart + 1, arrEnd - arrStart - 1)

    Dim idx As Long
    Dim pos As Long
    Dim token As String
    Dim ch As String
    idx = 0
    token = ""

    For pos = 1 To Len(content)
        ch = Mid(content, pos, 1)
        If ch = "," Then
            If idx <= UBound(result) Then
                result(idx) = ParseJsonNumber(Trim(token))
            End If
            idx = idx + 1
            token = ""
        Else
            token = token & ch
        End If
    Next pos

    ' Last token
    If idx <= UBound(result) Then
        result(idx) = ParseJsonNumber(Trim(token))
    End If

    ParseValuesArray = result
End Function

Private Function ParseJsonNumber(s As String) As Double
    If s = "" Or s = "null" Or s = "None" Then
        ParseJsonNumber = 0#
    ElseIf IsNumeric(s) Then
        ParseJsonNumber = CDbl(s)
    Else
        ParseJsonNumber = 0#
    End If
End Function

' ── Parse EPM formula arguments from a cell ─────────────────

Private Function ResolveEpmArgs(cell As Range) As Object
    On Error GoTo ParseError

    Dim f As String
    f = cell.Formula

    ' Determine which function and its defaults
    Dim funcName As String
    Dim defaultMeasure As String
    Dim defaultScenario As String
    Dim uf As String
    uf = UCase(f)

    defaultMeasure = "period_net_amount"
    defaultScenario = "actuals"

    If InStr(uf, "EPM_BUDGET(") > 0 Then
        funcName = "EPM_BUDGET"
        defaultMeasure = "period_amount"
        defaultScenario = "budget"
    ElseIf InStr(uf, "EPM_VARIANCE(") > 0 Then
        funcName = "EPM_VARIANCE"
        defaultMeasure = "variance_abs"
        defaultScenario = "variance"
    ElseIf InStr(uf, "EPM_DEBIT(") > 0 Then
        funcName = "EPM_DEBIT"
        defaultMeasure = "period_debit"
    ElseIf InStr(uf, "EPM_CREDIT(") > 0 Then
        funcName = "EPM_CREDIT"
        defaultMeasure = "period_credit"
    Else
        funcName = "EPM"
    End If

    ' Find the function call
    Dim funcPos As Long
    funcPos = InStr(uf, funcName & "(")
    If funcPos = 0 Then
        Set ResolveEpmArgs = Nothing
        Exit Function
    End If

    Dim parenPos As Long
    parenPos = funcPos + Len(funcName)

    ' Extract arguments between the parentheses
    Dim depth As Long
    Dim argStart As Long
    Dim argList(0 To 8) As String
    Dim argCount As Long
    Dim ch As String
    Dim pos As Long

    depth = 0
    argStart = parenPos + 1
    argCount = 0

    For pos = parenPos To Len(f)
        ch = Mid(f, pos, 1)
        If ch = "(" Then
            depth = depth + 1
        ElseIf ch = ")" Then
            depth = depth - 1
            If depth = 0 Then
                If pos > argStart Then
                    argList(argCount) = Mid(f, argStart, pos - argStart)
                    argCount = argCount + 1
                End If
                Exit For
            End If
        ElseIf ch = "," And depth = 1 Then
            argList(argCount) = Mid(f, argStart, pos - argStart)
            argCount = argCount + 1
            argStart = pos + 1
        End If
    Next pos

    If argCount < 4 Then
        Set ResolveEpmArgs = Nothing
        Exit Function
    End If

    ' Evaluate each argument (resolves cell references like $B$5)
    Dim entity As String
    Dim yr As Long
    Dim per As String
    Dim account As String
    Dim measure As String
    Dim scenario As String
    Dim costCenter As String
    Dim department As String
    Dim scenarioId As String

    entity = CStr(EvalArg(cell, argList(0)))
    yr = CLng(EvalArg(cell, argList(1)))
    per = CStr(EvalArg(cell, argList(2)))
    account = CStr(EvalArg(cell, argList(3)))

    If funcName = "EPM" Then
        If argCount > 4 Then measure = CStr(EvalArg(cell, argList(4))) Else measure = defaultMeasure
        If argCount > 5 Then scenario = CStr(EvalArg(cell, argList(5))) Else scenario = defaultScenario
        If argCount > 6 Then costCenter = CStr(EvalArg(cell, argList(6))) Else costCenter = ""
        If argCount > 7 Then department = CStr(EvalArg(cell, argList(7))) Else department = ""
        If argCount > 8 Then scenarioId = CStr(EvalArg(cell, argList(8))) Else scenarioId = ""
    Else
        measure = defaultMeasure
        scenario = defaultScenario
        If argCount > 4 Then costCenter = CStr(EvalArg(cell, argList(4))) Else costCenter = ""
        If argCount > 5 Then department = CStr(EvalArg(cell, argList(5))) Else department = ""
        If argCount > 6 Then scenarioId = CStr(EvalArg(cell, argList(6))) Else scenarioId = ""
    End If

    ' Build result dictionary
    Dim result As Object
    Set result = CreateObject("Scripting.Dictionary")
    result.Add "entity", entity
    result.Add "year", yr
    result.Add "period", per
    result.Add "account", account
    result.Add "measure", measure
    result.Add "scenario", scenario
    result.Add "cost_center", costCenter
    result.Add "department", department
    result.Add "scenario_id", scenarioId
    result.Add "key", BuildKey(entity, yr, per, account, measure, scenario, costCenter, department, scenarioId)

    Set ResolveEpmArgs = result
    Exit Function

ParseError:
    Set ResolveEpmArgs = Nothing
End Function

' ── Evaluate a formula argument (resolve cell refs) ─────────

Private Function EvalArg(cell As Range, arg As String) As Variant
    arg = Trim(arg)
    If arg = "" Then
        EvalArg = ""
        Exit Function
    End If

    ' Remove surrounding quotes for string literals
    If Left(arg, 1) = """" And Right(arg, 1) = """" Then
        EvalArg = Mid(arg, 2, Len(arg) - 2)
        Exit Function
    End If

    ' If it's a number
    If IsNumeric(arg) Then
        EvalArg = CDbl(arg)
        Exit Function
    End If

    ' Try to evaluate as cell reference
    On Error GoTo EvalFail
    EvalArg = cell.Worksheet.Evaluate(arg)
    Exit Function

EvalFail:
    EvalArg = arg
End Function

' ── Logging ─────────────────────────────────────────────────

Public Sub EPM_ToggleLog()
    pLoggingEnabled = Not pLoggingEnabled
    If pLoggingEnabled Then
        MsgBox "Logging enabled. Messages will appear in the _EPM_Log sheet.", vbInformation, "Open EPM"
    Else
        MsgBox "Logging disabled.", vbInformation, "Open EPM"
    End If
End Sub

Private Sub LogMsg(level As String, msg As String)
    If Not pLoggingEnabled Then Exit Sub
    Dim ws As Worksheet
    Dim nextRow As Long

    On Error Resume Next
    Set ws = ActiveWorkbook.Sheets(LOG_SHEET_NAME)
    On Error GoTo 0

    If ws Is Nothing Then
        Set ws = ActiveWorkbook.Sheets.Add(After:=ActiveWorkbook.Sheets(ActiveWorkbook.Sheets.Count))
        ws.Name = LOG_SHEET_NAME
        ws.Visible = xlSheetVisible
        ws.Cells(1, 1).Value = "Timestamp"
        ws.Cells(1, 2).Value = "Level"
        ws.Cells(1, 3).Value = "Message"
        ws.Rows(1).Font.Bold = True
        ws.Columns(1).ColumnWidth = 20
        ws.Columns(2).ColumnWidth = 8
        ws.Columns(3).ColumnWidth = 80
    End If

    nextRow = ws.Cells(ws.Rows.Count, 1).End(xlUp).Row + 1
    ws.Cells(nextRow, 1).Value = Format(Now, "yyyy-mm-dd hh:nn:ss")
    ws.Cells(nextRow, 2).Value = level
    ws.Cells(nextRow, 3).Value = msg
End Sub

' ── Helpers ───────────────────────────────────────────────────

Private Function BuildKey(entity As String, yr As Long, per As String, _
    account As String, measure As String, scenario As String, _
    costCenter As String, department As String, _
    Optional scenarioId As String = "") As String
    BuildKey = entity & "|" & yr & "|" & per & "|" & account & "|" & _
               measure & "|" & scenario & "|" & costCenter & "|" & department & _
               "|" & scenarioId
End Function

Private Function JsonEscape(s As String) As String
    s = Replace(s, "\", "\\")
    s = Replace(s, """", "\""")
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    s = Replace(s, vbTab, " ")
    JsonEscape = s
End Function

' ── Server configuration ────────────────────────────────────

Public Sub EPM_SetServer()
    Dim url As String
    url = InputBox("Enter the Open EPM API server URL:", "Open EPM", API_BASE_URL)
    If url = "" Then Exit Sub

    pApiUrl = url

    ' Save to workbook custom properties (4 = msoPropertyTypeString)
    On Error Resume Next
    ActiveWorkbook.CustomDocumentProperties("EPM_API_URL").Value = url
    If Err.Number <> 0 Then
        Err.Clear
        ActiveWorkbook.CustomDocumentProperties.Add _
            Name:="EPM_API_URL", LinkToContent:=False, _
            Type:=4, Value:=url
    End If
    On Error GoTo 0

    MsgBox "API URL set to: " & url, vbInformation, "Open EPM"
End Sub

' ── Status bar cleanup ──────────────────────────────────────

Public Sub ClearStatusBar()
    Application.StatusBar = False
End Sub

' ── Auto-bind Ctrl+Shift+R on workbook open ─────────────────

Public Sub Workbook_Open()
    EnsureCache
    LogMsg "INFO", "Open EPM loaded (server: " & API_BASE_URL & ")"
    Application.OnKey "+^r", "EPM_Refresh"
    Application.StatusBar = "Open EPM loaded. Ctrl+Shift+R to refresh."
    Application.OnTime Now + TimeValue("00:00:03"), "ClearStatusBar"
End Sub

Public Sub Auto_Open()
    Workbook_Open
End Sub

Public Sub Auto_Close()
    Application.OnKey "+^r"
End Sub

Private Function EnsureLogin() As Boolean
    If pLoggedIn And pSessionCookie <> "" Then
        EnsureLogin = True
        Exit Function
    End If
    EPM_Login
    EnsureLogin = pLoggedIn
End Function

' ── Budget Save (write-back from Excel) ─────────────────────
'
' EPM_BUDGET_SAVE scans a budget template sheet and POSTs budget lines
' to Frappe. The template layout expects:
'   Row 1: Headers (Entity, Account, CostCenter, Department, P1..P12)
'   Row 2+: Data rows
'
' The scenario_id and fiscal_year are read from named ranges or cells:
'   - Named range "BudgetScenario" or cell A1 of a "Config" sheet
'   - Named range "BudgetYear" or cell B1 of a "Config" sheet
'
Public Sub EPM_BUDGET_SAVE()
    If Not EnsureLogin Then Exit Sub

    Dim ws As Worksheet
    Set ws = ActiveSheet

    ' Read scenario and year from named ranges or config
    Dim scenarioId As String
    Dim fiscalYear As Long
    On Error Resume Next
    scenarioId = Range("BudgetScenario").Value
    fiscalYear = CLng(Range("BudgetYear").Value)
    On Error GoTo 0

    If scenarioId = "" Then
        scenarioId = InputBox("Enter Scenario ID (e.g. budget_2025):", "Budget Save")
        If scenarioId = "" Then Exit Sub
    End If
    If fiscalYear = 0 Then
        Dim yrStr As String
        yrStr = InputBox("Enter Fiscal Year:", "Budget Save")
        If yrStr = "" Then Exit Sub
        fiscalYear = CLng(yrStr)
    End If

    ' Detect columns: find P1-P12 header columns
    Dim lastCol As Long
    lastCol = ws.Cells(1, ws.Columns.Count).End(xlToLeft).Column
    Dim periodCols(1 To 12) As Long
    Dim col As Long
    Dim hdr As String
    For col = 1 To lastCol
        hdr = UCase(Trim(ws.Cells(1, col).Value))
        If Left(hdr, 1) = "P" And Len(hdr) <= 3 Then
            Dim pNum As Long
            On Error Resume Next
            pNum = CLng(Mid(hdr, 2))
            On Error GoTo 0
            If pNum >= 1 And pNum <= 12 Then
                periodCols(pNum) = col
            End If
        End If
    Next col

    ' Detect entity, account, cost_center, department columns
    Dim entityCol As Long, accountCol As Long
    Dim ccCol As Long, deptCol As Long
    entityCol = 0: accountCol = 0: ccCol = 0: deptCol = 0
    For col = 1 To lastCol
        hdr = UCase(Trim(ws.Cells(1, col).Value))
        Select Case hdr
            Case "ENTITY", "DATA_AREA_ID": entityCol = col
            Case "ACCOUNT", "MAIN_ACCOUNT": accountCol = col
            Case "COST_CENTER", "COSTCENTER", "DIM_COST_CENTER": ccCol = col
            Case "DEPARTMENT", "DIM_DEPARTMENT": deptCol = col
        End Select
    Next col

    If entityCol = 0 Or accountCol = 0 Then
        MsgBox "Cannot find Entity and Account columns in row 1.", vbExclamation, "Budget Save"
        Exit Sub
    End If

    ' Build JSON array of budget lines
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, entityCol).End(xlUp).Row
    If lastRow < 2 Then
        MsgBox "No data rows found.", vbInformation, "Budget Save"
        Exit Sub
    End If

    Dim jsonLines As String
    Dim lineCount As Long
    jsonLines = "["
    lineCount = 0

    Dim r As Long
    For r = 2 To lastRow
        Dim entity As String, account As String
        entity = Trim(CStr(ws.Cells(r, entityCol).Value))
        account = Trim(CStr(ws.Cells(r, accountCol).Value))
        If entity = "" Or account = "" Then GoTo NextRow

        Dim cc As String, dept As String
        cc = ""
        dept = ""
        If ccCol > 0 Then cc = Trim(CStr(ws.Cells(r, ccCol).Value))
        If deptCol > 0 Then dept = Trim(CStr(ws.Cells(r, deptCol).Value))

        ' Build periods array
        Dim periodsJson As String
        periodsJson = "["
        Dim p As Long
        Dim hasPeriod As Boolean
        hasPeriod = False
        For p = 1 To 12
            If periodCols(p) > 0 Then
                Dim amt As Double
                amt = 0
                On Error Resume Next
                amt = CDbl(ws.Cells(r, periodCols(p)).Value)
                On Error GoTo 0
                If hasPeriod Then periodsJson = periodsJson & ","
                periodsJson = periodsJson & "{""period"":" & p & ",""amount"":" & amt & "}"
                hasPeriod = True
            End If
        Next p
        periodsJson = periodsJson & "]"

        If lineCount > 0 Then jsonLines = jsonLines & ","
        jsonLines = jsonLines & "{" & _
            """scenario_id"":""" & JsonEscape(scenarioId) & """," & _
            """data_area_id"":""" & JsonEscape(entity) & """," & _
            """fiscal_year"":" & fiscalYear & "," & _
            """main_account"":""" & JsonEscape(account) & """," & _
            """dim_cost_center"":""" & JsonEscape(cc) & """," & _
            """dim_department"":""" & JsonEscape(dept) & """," & _
            """periods"":" & periodsJson & "}"
        lineCount = lineCount + 1

        Application.StatusBar = "Saving " & lineCount & " budget lines..."
NextRow:
    Next r
    jsonLines = jsonLines & "]"

    If lineCount = 0 Then
        MsgBox "No valid budget lines found.", vbInformation, "Budget Save"
        Exit Sub
    End If

    ' POST to budget_save_batch
    Dim http As Object
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    Dim url As String
    url = API_BASE_URL & "/api/method/konsol.api.budget_save_batch"

    On Error GoTo BudgetSaveFail
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    If pSessionCookie <> "" Then http.setRequestHeader "Cookie", pSessionCookie
    http.send jsonLines

    Application.StatusBar = False

    If http.Status = 200 Then
        LogMsg "INFO", "Budget save: " & lineCount & " lines saved"
        MsgBox lineCount & " budget lines saved successfully.", vbInformation, "Budget Save"
    Else
        LogMsg "ERROR", "Budget save failed: HTTP " & http.Status & " " & http.responseText
        MsgBox "Budget save failed (HTTP " & http.Status & "):" & vbCrLf & _
               Left(http.responseText, 500), vbExclamation, "Budget Save"
    End If
    Exit Sub

BudgetSaveFail:
    Application.StatusBar = False
    LogMsg "ERROR", "Budget save error: " & Err.Description
    MsgBox "Budget save error: " & Err.Description, vbExclamation, "Budget Save"
End Sub

' ── Debug: test connectivity and formula scanning ─────────
Public Sub EPM_Debug()
    Dim msg As String
    msg = "=== EPM Debug ===" & vbCrLf

    ' Test 1: Cache
    EnsureCache
    msg = msg & "Cache: OK" & vbCrLf

    ' Test 2: HTTP connectivity
    Dim http As Object
    On Error Resume Next
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    If Err.Number <> 0 Then
        msg = msg & "HTTP object: FAILED - " & Err.Description & vbCrLf
        MsgBox msg, vbExclamation, "EPM Debug"
        Exit Sub
    End If
    msg = msg & "HTTP object: OK" & vbCrLf

    Dim url As String
    url = API_BASE_URL & "/api/method/konsol.api.health"
    http.Open "GET", url, False
    If pSessionCookie <> "" Then http.setRequestHeader "Cookie", pSessionCookie
    http.send
    If Err.Number <> 0 Then
        msg = msg & "GET " & url & ": FAILED - " & Err.Description & vbCrLf
        MsgBox msg, vbExclamation, "EPM Debug"
        Exit Sub
    End If
    msg = msg & "GET " & url & ": " & http.Status & " " & http.responseText & vbCrLf
    On Error GoTo 0

    ' Test 3: Scan formulas
    Dim ws As Worksheet
    Set ws = ActiveSheet
    Dim usedRange As Range
    Set usedRange = ws.usedRange
    Dim epmCount As Long
    Dim r As Long, c As Long
    Dim cell As Range
    Dim f As String
    epmCount = 0

    For r = 1 To usedRange.Rows.Count
        For c = 1 To usedRange.Columns.Count
            Set cell = usedRange.Cells(r, c)
            If cell.HasFormula Then
                f = UCase(cell.Formula)
                If InStr(f, "EPM(") > 0 Or InStr(f, "EPM_BUDGET(") > 0 Or _
                   InStr(f, "EPM_VARIANCE(") > 0 Then
                    epmCount = epmCount + 1
                    If epmCount <= 3 Then
                        msg = msg & "Found: " & cell.Address & " = " & Left(cell.Formula, 60) & vbCrLf

                        ' Try to resolve args
                        Dim args As Object
                        Set args = ResolveEpmArgs(cell)
                        If args Is Nothing Then
                            msg = msg & "  -> ResolveEpmArgs returned Nothing!" & vbCrLf
                        Else
                            msg = msg & "  -> entity=" & args("entity") & " yr=" & args("year") & _
                                        " per=" & args("period") & " acct=" & args("account") & vbCrLf
                        End If
                    End If
                End If
            End If
        Next c
    Next r
    msg = msg & "Total EPM formulas found: " & epmCount & vbCrLf

    ' Test 4: Try a single batch call
    If epmCount > 0 Then
        Dim testJson As String
        testJson = "[{""entity"":""USMF"",""year"":2024,""period"":5,""account"":""401100"",""measure"":""period_net_amount"",""scenario"":""actuals""}]"

        On Error Resume Next
        Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
        url = API_BASE_URL & "/api/method/konsol.api.epm_batch"
        http.Open "POST", url, False
        http.setRequestHeader "Content-Type", "application/json"
        If pSessionCookie <> "" Then http.setRequestHeader "Cookie", pSessionCookie
        http.send testJson
        If Err.Number <> 0 Then
            msg = msg & "POST batch: FAILED - " & Err.Description & vbCrLf
        Else
            msg = msg & "POST batch: " & http.Status & " " & http.responseText & vbCrLf
        End If
        On Error GoTo 0
    End If

    MsgBox msg, vbInformation, "EPM Debug"
End Sub
