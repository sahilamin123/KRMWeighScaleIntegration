' KRM Weigh Scale Integration
' Polls a weight-scale API at a configurable interval and logs non-idle
' weight readings (with timestamp) to a text file.
'
' Run with:  cscript main.vbs
' All settings live in config.ini (same directory as this script).

Option Explicit

' ---------------------------------------------------------------------------
' Constants
' ---------------------------------------------------------------------------

Dim SCRIPT_DIR
SCRIPT_DIR = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

Dim CONFIG_FILE
CONFIG_FILE = SCRIPT_DIR & "config.ini"

' Idle / no-load sentinel: STX (Chr(2)) + "1      00    00"
Dim IDLE_WEIGHT
IDLE_WEIGHT = Chr(2) & "1      00    00"

' ---------------------------------------------------------------------------
' INI reader
' ---------------------------------------------------------------------------

Function ReadIni(sFile, sSection, sKey, sDefault)
    Dim oFSO, oFile, sLine, sCurrentSection, eqPos, k, v, cPos
    Set oFSO = CreateObject("Scripting.FileSystemObject")
    If Not oFSO.FileExists(sFile) Then
        WScript.Echo "ERROR: Configuration file not found: " & sFile
        WScript.Quit 1
    End If
    Set oFile = oFSO.OpenTextFile(sFile, 1)
    sCurrentSection = ""
    ReadIni = sDefault
    Do While Not oFile.AtEndOfStream
        sLine = Trim(oFile.ReadLine())
        If Left(sLine, 1) = "[" And Right(sLine, 1) = "]" Then
            sCurrentSection = Mid(sLine, 2, Len(sLine) - 2)
        ElseIf sCurrentSection = sSection Then
            eqPos = InStr(sLine, "=")
            If eqPos > 0 Then
                k = Trim(Left(sLine, eqPos - 1))
                v = Trim(Mid(sLine, eqPos + 1))
                ' Strip inline comments
                cPos = InStr(v, " #")
                If cPos > 0 Then v = Trim(Left(v, cPos - 1))
                If k = sKey Then ReadIni = v
            End If
        End If
    Loop
    oFile.Close
End Function

' ---------------------------------------------------------------------------
' Logging
' ---------------------------------------------------------------------------

Dim g_LogFile
g_LogFile = ""

Sub LogMessage(sMsg)
    Dim oFSO, oFile, ts, sLine
    ts = Now()
    sLine = Year(ts) & "-" & _
            Right("0" & Month(ts), 2) & "-" & _
            Right("0" & Day(ts), 2) & " " & _
            Right("0" & Hour(ts), 2) & ":" & _
            Right("0" & Minute(ts), 2) & ":" & _
            Right("0" & Second(ts), 2) & "  " & sMsg
    Set oFSO = CreateObject("Scripting.FileSystemObject")
    Set oFile = oFSO.OpenTextFile(g_LogFile, 8, True)  ' 8 = ForAppending, create if missing
    oFile.WriteLine sLine
    oFile.Close
    WScript.Echo sLine
End Sub

Sub WarnMessage(sMsg)
    On Error Resume Next
    WScript.StdErr.WriteLine "WARNING: " & sMsg
    If Err.Number <> 0 Then
        WScript.Echo "WARNING: " & sMsg
        Err.Clear
    End If
    On Error GoTo 0
End Sub

' ---------------------------------------------------------------------------
' Minimal JSON helpers
' ---------------------------------------------------------------------------

Function GetJsonBool(sJson, sKey)
    ' Returns True if "key": true is present, False otherwise.
    Dim pos, rest
    pos = InStr(sJson, """" & sKey & """:")
    If pos = 0 Then
        GetJsonBool = False
        Exit Function
    End If
    rest = Trim(Mid(sJson, pos + Len(sKey) + 3))
    GetJsonBool = (Left(rest, 4) = "true")
End Function

Function GetJsonString(sJson, sKey)
    ' Returns the raw (still-escaped) string value for "key": "value".
    Dim pos, rest, endPos
    pos = InStr(sJson, """" & sKey & """:")
    If pos = 0 Then
        GetJsonString = ""
        Exit Function
    End If
    rest = Trim(Mid(sJson, pos + Len(sKey) + 3))
    If Left(rest, 1) <> """" Then
        GetJsonString = ""
        Exit Function
    End If
    rest = Mid(rest, 2)  ' skip opening quote
    endPos = 1
    Do While endPos <= Len(rest)
        If Mid(rest, endPos, 1) = "\" Then
            endPos = endPos + 2  ' skip escape sequence
        ElseIf Mid(rest, endPos, 1) = """" Then
            Exit Do
        Else
            endPos = endPos + 1
        End If
    Loop
    GetJsonString = Left(rest, endPos - 1)
End Function

Function UnescapeJson(s)
    ' Converts JSON escape sequences to their character equivalents.
    Dim i, out, hexStr
    i = 1
    out = ""
    Do While i <= Len(s)
        If Mid(s, i, 2) = "\u" And i + 5 <= Len(s) Then
            hexStr = Mid(s, i + 2, 4)
            out = out & ChrW(CLng("&H" & hexStr))
            i = i + 6
        ElseIf Mid(s, i, 2) = "\n" Then
            out = out & Chr(10) : i = i + 2
        ElseIf Mid(s, i, 2) = "\r" Then
            out = out & Chr(13) : i = i + 2
        ElseIf Mid(s, i, 2) = "\t" Then
            out = out & Chr(9)  : i = i + 2
        ElseIf Mid(s, i, 2) = "\\" Then
            out = out & "\"     : i = i + 2
        ElseIf Mid(s, i, 2) = "\""" Then
            out = out & """"    : i = i + 2
        Else
            out = out & Mid(s, i, 1) : i = i + 1
        End If
    Loop
    UnescapeJson = out
End Function

' ---------------------------------------------------------------------------
' HTTP fetch
' ---------------------------------------------------------------------------

Function FetchWeight(sUrl, nTimeoutSec)
    ' Returns the response body string, or "" on any error.
    On Error Resume Next
    Dim oHttp
    Set oHttp = CreateObject("WinHttp.WinHttpRequest.5.1")
    oHttp.Open "GET", sUrl, False
    ' SetTimeouts(resolveTimeout, connectTimeout, sendTimeout, receiveTimeout) in ms
    oHttp.SetTimeouts nTimeoutSec * 1000, nTimeoutSec * 1000, _
                      nTimeoutSec * 1000, nTimeoutSec * 1000
    oHttp.Send
    If Err.Number <> 0 Then
        WarnMessage "Could not connect to " & sUrl & " (" & Err.Description & ")"
        Err.Clear
        FetchWeight = ""
        On Error GoTo 0
        Exit Function
    End If
    If oHttp.Status < 200 Or oHttp.Status >= 300 Then
        WarnMessage "HTTP error from " & sUrl & ": " & oHttp.Status
        FetchWeight = ""
        On Error GoTo 0
        Exit Function
    End If
    FetchWeight = oHttp.ResponseText
    On Error GoTo 0
End Function

' ---------------------------------------------------------------------------
' Main
' ---------------------------------------------------------------------------

Dim api_url, poll_interval, log_file, request_timeout
api_url         = ReadIni(CONFIG_FILE, "settings", "api_url",                    "http://localhost:8080/api/weight/get-weight")
poll_interval   = CInt(ReadIni(CONFIG_FILE, "settings", "poll_interval_seconds",   "5"))
log_file        = ReadIni(CONFIG_FILE, "settings", "log_file",                   "weight_log.txt")
request_timeout = CInt(ReadIni(CONFIG_FILE, "settings", "request_timeout_seconds", "10"))

' Resolve a relative log-file path to the script directory
If Mid(log_file, 2, 2) <> ":\" And Left(log_file, 2) <> "\\" Then
    log_file = SCRIPT_DIR & log_file
End If
g_LogFile = log_file

LogMessage "=== KRM Weigh Scale Integration started ==="
LogMessage "API URL       : " & api_url
LogMessage "Poll interval : " & poll_interval & " seconds"
LogMessage "Log file      : " & log_file

Dim jsonResponse, weight
Do
    jsonResponse = FetchWeight(api_url, request_timeout)

    If jsonResponse <> "" Then
        If Not GetJsonBool(jsonResponse, "success") Then
            WarnMessage "API returned success=false"
        Else
            weight = UnescapeJson(GetJsonString(jsonResponse, "weight"))
            If weight <> IDLE_WEIGHT Then
                LogMessage "Weight: " & weight
            End If
        End If
    End If

    WScript.Sleep poll_interval * 1000
Loop
