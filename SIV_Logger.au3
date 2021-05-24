#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_UseX64=n
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.14.5
 Author:         Alex 'Monoxid' W., Kevin 'DJDeagle' M.

 Licence:
   The Settlers IV-Logger (c) by Alex 'Monoxid' W. and Kevin 'DJDeagle' M.

   The Settlers IV-Logger is licensed under a
   Creative Commons Attribution-ShareAlike 4.0 International License.

    You should have received a copy of the license along with this
    work. If not, see <http://creativecommons.org/licenses/by-sa/4.0/>.

 Script Function:
	Loggt Werte definiert in einer CSV aus einer laufenden Die Siedler IV Partie
	in ein CSV File

#ce ----------------------------------------------------------------------------

; Kevins gute Idee für saubere Daten:		:-)
; Loggen Start möglich aber erst wenn Siedler <> 0 dann Logdaten schreiben	-- Start der Partie abfangen
; Sobald dann Siedler = 0 Log stoppen und keinen Eintrag mehr schreiben		-- Ende der Partie abfangen


#include <GUIConstantsEx.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <Array.au3>
#include <WinAPIProc.au3>
#include <WinAPIMem.au3>
#include <WinAPIHObj.au3>
#include <WinAPIError.au3>
#include <ProcessConstants.au3>
#include <WindowsConstants.au3>
#include <Date.au3>
#include <TrayConstants.au3>

$sNow = _Now()
$sNow = StringReplace($sNow, "/", "-")
$sNow = StringReplace($sNow, "\", "-")
$sNow = StringReplace($sNow, ".", "-")
$sNow = StringReplace($sNow, ":", "-")
$sNow = StringReplace($sNow, " ", "_")

; Konfiguration
$sFileIn = "list.csv"
$sFileOut = "logs/statlog_" & @UserName & "_" & $sNow & ".csv"
$iDelay = 5000

; Programmcode
Opt("GUIOnEventMode", 1)

$iPID = WinGetProcess("Die Siedler IV")
If $iPID == -1 Then Exit 10

$bLoggingEnabled = False

Global $iPlayerOffset = Number(InputBox("Siedler IV - Statlogger", "Welcher Spieler soll geloggt werden?", "1"))
If @error Or $iPlayerOffset < 1 Or $iPlayerOffset > 8 Then
	MsgBox(0, "", "Du doof! Gibt doch nur Spieler 1-8...")
	Exit 1
EndIf

; Korrekten Offset berechnen
$iPlayerOffset = ($iPlayerOffset-1) * 4392

Local $__tMode = DllStructCreate("ptr;ptr;int")
$__pBuf = DllStructGetPtr($__tMode, 3)

$pBaseAddress =_MemoryModuleGetBaseAddress($iPID, "S4_Main.exe")

; Static Pointer auf die aktuelle Turmanzahl von Spieler 1
$hOffset = "0x000F8ED4"
$iBaseOffset = 196

ConsoleWrite("Basisadresse: " & $pBaseAddress & @CRLF)
ConsoleWrite("Basisoffset: " & $hOffset & @CRLF)

Global $__hProcess = _WinAPI_OpenProcess($PROCESS_VM_READ, 0, $iPID, True)
If @error Then ErrorFunc(1)

; Basisadresse berechnen
$pStartingPointer = $pBaseAddress+$hOffset
DllStructSetData($__tMode, 1, $pStartingPointer)

ConsoleWrite("Round 1: GET: " & DllStructGetData($__tMode, 1) & " = ")

$iBytesRead = 0
$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, DLLStructGetData($__tMode, 1), DLLStructGetPtr($__tMode, 2), 4, $iBytesRead)
If Not $bSuccess Then ErrorFunc(3)

ConsoleWrite(DllStructGetData($__tMode, 2) & @CRLF)
$pBaseAddress = DllStructGetData($__tMode, 2)


Dim $aOffsetList
_FileReadToArray($sFileIn, $aOffsetList, $FRTA_COUNT, @TAB)

$fHndStatOut = FileOpen($sFileOut, $FO_APPEND)
$sFirstLine = "Zeitstempel" & @TAB & "Zähler" & @TAB
For $i = 1 To $aOffsetList[0][0]
	$sFirstLine = $sFirstLine & $aOffsetList[$i][2] & " - " & $aOffsetList[$i][1] & @TAB
Next
FileWriteLine($fHndStatOut, $sFirstLine)
$iCounter = 0

$hGUI = GUICreate("Siedler IV - Statlogger by KEVLEX", 200, 60, Default, Default, BitOR($GUI_SS_DEFAULT_GUI, $WS_SIZEBOX))
GUISetOnEvent($GUI_EVENT_CLOSE, "CLOSEButton")

$idStart = GUICtrlCreateButton("Start", 10, 10, 85, 40)
GUICtrlSetFont(-1, 16, 500)
GUICtrlSetOnEvent(-1, "ToggleLogging")

$idStop = GUICtrlCreateButton("Stop", 105, 10, 85, 40)
GUICtrlSetFont(-1, 16, 500)
GUICtrlSetState(-1, $GUI_DISABLE)
GUICtrlSetOnEvent(-1, "ToggleLogging")

GUISetState(@SW_SHOW, $hGUI)

HotKeySet("{PAUSE}", "ToggleLogging")

While 1
	If Not ProcessExists($iPID) Then CLOSEButton()

	If $bLoggingEnabled Then
		$iCounter = $iCounter + 1
		$sNewLine = _Now() & @TAB & $iCounter & @TAB

		For $i = 1 To $aOffsetList[0][0]
			$iValue = GetData($pBaseAddress, $aOffsetList[$i][0], $iBaseOffset, $iPlayerOffset)
			$sNewLine = $sNewLine & $iValue & @TAB
		Next

		; Letztes Trennzeichen entfernen
		$sNewLine = StringTrimRight($sNewLine, 1)

		;ConsoleWrite($sNewLine & @CRLF)
		FileWriteLine($fHndStatOut, $sNewLine)
	EndIf

	Sleep($iDelay)
WEnd


Func ErrorFunc($iVal)
	$iLastError = _WinAPI_GetLastError()
	$sLastError = _WinAPI_GetLastErrorMessage()

	MsgBox(0, $iVal & ":" & $iLastError, $sLastError)

	_WinAPI_CloseHandle($__hProcess)

	Exit 10
EndFunc

Func CLOSEButton()
	FileClose($fHndStatOut)
	GUIDelete($hGUI)
	_WinAPI_CloseHandle($__hProcess)
    Exit 0
EndFunc


Func ToggleLogging()
	If $bLoggingEnabled Then
		$bLoggingEnabled = False
		FileFlush($fHndStatOut)
		GUICtrlSetState($idStop, $GUI_DISABLE)
		GUICtrlSetState($idStart, $GUI_ENABLE)

		TrayTip("Siedler IV Statlogger", "Logging deaktiviert", 10, $TIP_ICONASTERISK)
	Else
		$bLoggingEnabled = True
		GUICtrlSetState($idStop, $GUI_ENABLE)
		GUICtrlSetState($idStart, $GUI_DISABLE)

		TrayTip("Siedler IV Statlogger", "Logging aktiviert", 10, $TIP_ICONASTERISK)
	EndIf
EndFunc

Func GetData($_pBaseAddress, $_iOffset, $_iBaseOffset, $_iPlayerOffset)
	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $_pBaseAddress+$_iBaseOffset+$_iPlayerOffset+$_iOffset, $__pBuf, 4, $iBytesRead)
	If Not $bSuccess Then ErrorFunc(3)

#cs
	If $_iOffset = 0 Then
		ConsoleWrite("Calculated address: " & $_pBaseAddress+$_iBaseOffset+$_iOffset & @CRLF)
		ConsoleWrite("_pBaseAddress: " & $_pBaseAddress & @CRLF)
		ConsoleWrite("_iBaseOffset: " & $_iBaseOffset & @CRLF)
		ConsoleWrite("_iOffset: " & $_iOffset & @CRLF)
	EndIf
#ce

	Return DllStructGetData($__tMode, 3)
EndFunc

Func _MemoryModuleGetBaseAddress($iPID, $sModule)
    If Not ProcessExists($iPID) Then Return SetError(1, 0, 0)

    If Not IsString($sModule) Then Return SetError(2, 0, 0)

    Local   $PSAPI = DllOpen("psapi.dll")

    ;Get Process Handle
    Local   $hProcess
    Local   $PERMISSION = BitOR(0x0002, 0x0400, 0x0008, 0x0010, 0x0020) ; CREATE_THREAD, QUERY_INFORMATION, VM_OPERATION, VM_READ, VM_WRITE

    If $iPID > 0 Then
        Local $hProcess = DllCall("kernel32.dll", "ptr", "OpenProcess", "dword", $PERMISSION, "int", 0, "dword", $iPID)
        If $hProcess[0] Then
            $hProcess = $hProcess[0]
        EndIf
    EndIf

    ;EnumProcessModules
    Local   $Modules = DllStructCreate("ptr[1024]")
    Local   $aCall = DllCall($PSAPI, "int", "EnumProcessModules", "ptr", $hProcess, "ptr", DllStructGetPtr($Modules), "dword", DllStructGetSize($Modules), "dword*", 0)
    If $aCall[4] > 0 Then
        Local   $iModnum = $aCall[4] / 4
        Local   $aTemp
        For $i = 1 To $iModnum
            $aTemp =  DllCall($PSAPI, "dword", "GetModuleBaseNameW", "ptr", $hProcess, "ptr", Ptr(DllStructGetData($Modules, 1, $i)), "wstr", "", "dword", 260)
            If $aTemp[3] = $sModule Then
                DllClose($PSAPI)
                Return Ptr(DllStructGetData($Modules, 1, $i))
            EndIf
        Next
    EndIf

    DllClose($PSAPI)
    Return SetError(-1, 0, 0)

EndFunc