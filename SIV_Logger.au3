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

 Changelog:
	V2: Mehrere Spieler können mit einem Prozess geloggt werden
		Logging startet automatisch bei Partiestart und stoppt bei Partieende (Erkennung über GameTicks)
		Standardmäßig wird im Log nun die verstrichene Spielzeit verwendet statt der aktuellen PC-Zeit
		Neue Spalte in den Logfiles: Spieler
		Funktionen zur Berechnung der Pointer besser strukturiert und aufgetrennt in sinnvolle Teilfunktionen
		Basisoffset geändert, damit alle Datenoffsets positive Werte haben (Siehe Anpassung in .csv Inputfile)
		MustDeclareVars aktiviert, um undefiniertes Verhalten bei Variablen zu vermeiden
		Neues GUI mit Statusanzeige, Kartenname, Spieleranzahl, Spielernamen und verstrichener Zeit

	V3: Daten aus RAM direkt in ein Array holen für mehr Performance
		Headerbereich im Output mit Spieleranzahl und Spielernamen

#ce ----------------------------------------------------------------------------

#include <GUIConstants.au3>
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

Opt('MustDeclareVars', 1)
Opt("GUIOnEventMode", 1)

; Konfiguration
Global $iLogInterval = 5000
Global $bUseRealtime = False	; PC Zeit statt Spielzeit verwenden
Global $sFileIn = "list.csv"
Global $sFileOut = "logs/statlog_" & @UserName & "_%NOW%.csv"

Global $__VERSION = "3"

Global $__iProcessID = -1, $__hProcess = Null
Global $__pPlayerBase[8] = [Null,Null,Null,Null,Null,Null,Null,Null], $__pThreadBaseAddress = Null, $__pTickAddress = Null
Global $__fHnd = Null, $__aOffsetList

Global $__aCheckbox[8], $__Edit1, $__Label4, $__ListView, $__ListViewItems[3]

Global $__bLoggingEnabled = True, $__bMatchInitialized = False
Global $__iLineCounter = 0

; Programmcode
Main()

Func Main()
	GetOffsetData()

	Local $hWinMain = GUICreate("SIV Logger " & $__VERSION, 352, 385)

	For $i = 0 To 7
		$__aCheckbox[$i] = GUICtrlCreateCheckbox("Spieler " & $i+1, 8, 25 + 16 * $i, 164, 16)
		GUICtrlSetState(-1, $GUI_CHECKED)
		GUICtrlSetFont(-1, Default, Default, Default, "Monospace")
	Next

	Local $Label1 = GUICtrlCreateLabel("Welche Statistiken sollen geloggt werden?", 8, 8, 336, 15)
	Local $Label2 = GUICtrlCreateLabel("Logging ist:", 8, 350, 85, 20, $SS_CENTERIMAGE)
	Local $Label5 = GUICtrlCreateLabel("Spielinformationen:", 8, 165, 164, 15)
	$__Label4 = GUICtrlCreateLabel("Inaktiv", 100, 350, 85, 20, $SS_CENTERIMAGE)
	Local $Label6 = GUICtrlCreateLabel("Programminformationen:", 180, 165, 164, 15)

	GUICtrlSetFont($Label2, 12, 400)
	GUICtrlSetFont($__Label4, 14, 400)
	GUICtrlSetFont($Label5, Default, 600)
	GUICtrlSetFont($Label6, Default, 600)

	$__Edit1 = GUICtrlCreateEdit("Suche Spiel...", 180, 185, 164, 150, BitOR($ES_WANTRETURN, $WS_VSCROLL, $ES_AUTOVSCROLL, $ES_READONLY))

	$__ListView = GUICtrlCreateListView("        Name|        Wert", 8, 185, 164, 150)
	$__ListViewItems[0] = GUICtrlCreateListViewItem("Karte|", $__ListView)
	$__ListViewItems[1] = GUICtrlCreateListViewItem("Spieleranzahl|", $__ListView)
	$__ListViewItems[2] = GUICtrlCreateListViewItem("Spielzeit|", $__ListView)

	GUISetOnEvent($GUI_EVENT_CLOSE, "CloseButton")
	GUISetState(@SW_SHOW)

	Local $bMatchRunningInfo = False
	Local $hLogTimerHandle = TimerInit()

	While 1
		If $__hProcess == Null Then
			If OpenProcess() Then
				GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Spiel gefunden" & @CRLF & "Warte auf Partiestart")
			EndIf
		Else
			If Not ProcessExists($__iProcessID) Then
				DisableLogging()
				LogFileClose()
				CloseProcess()
				GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Spiel beendet")
			Else
				If IsMatchRunning() Then
					GUICtrlSetData($__ListViewItems[2], "Spielzeit|" & GetElapsedGameTime())

					If Not $__bMatchInitialized Then
						$__bMatchInitialized = True

						GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Partie gestartet")

						For $i = 1 To GetPlayerCount()
							GUICtrlSetData($__aCheckbox[$i-1], GetPlayerName($i))
						Next

						GUICtrlSetData($__ListViewItems[0], "Karte|" & GetMapName())
						GUICtrlSetData($__ListViewItems[1], "Spieleranzahl|" & GetPlayerCount())
						GUICtrlSetData($__ListViewItems[2], "Spielzeit|" & GetElapsedGameTime())

						LogFileOpen()
						EnableLogging()
					EndIf

					If $__bLoggingEnabled AND TimerDiff($hLogTimerHandle) > $iLogInterval Then
						$hLogTimerHandle = TimerInit()
						LogData()
					EndIf
				Else
					If $__bMatchInitialized = True Then
						$__bMatchInitialized = False

						GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Partie beendet")

						GUICtrlSetData($__ListViewItems[0], "Karte|")
						GUICtrlSetData($__ListViewItems[1], "Spieleranzahl|")
						GUICtrlSetData($__ListViewItems[2], "Spielzeit|")

						DisableLogging()
						LogFileClose()

						For $i = 1 To 8
							GUICtrlSetData($__aCheckbox[$i-1], "Spieler " & $i)
						Next
					EndIf
				EndIf
			EndIf
		EndIf

		Sleep(500)
	WEnd
EndFunc

Func OpenProcess()
	Local $iProcessID = WinGetProcess("Die Siedler IV")
	If $iProcessID == -1 Then Return SetError(1, 0, False)

	Local $hProcess = _WinAPI_OpenProcess($PROCESS_VM_READ, 0, $iProcessID, True)
	If @error Then Return SetError(2, 0, False)

	GetThreadBaseAddress($hProcess, $iProcessID)
	If @error Then Return SetError(3, 0, False)

	GetPlayerBaseAddresses($hProcess, $iProcessID)
	If @error Then Return SetError(4, 0, False)

	$__iProcessID = $iProcessID
	$__hProcess = $hProcess
	Return True
EndFunc

Func CloseProcess()
	_WinAPI_CloseHandle($__hProcess)
	$__hProcess = Null
EndFunc

Func GetTicks()
	Static Local $pTicksAddress = $__pThreadBaseAddress + Ptr("0xE66B14")
	Static Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pTicksAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & "::" & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc


Func GetMapName()
	Local $tMode = DllStructCreate("ptr;wchar[32]")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0x109C0DC")
	Local $sMapname, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1)

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 2), 32, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$sMapname = DllStructGetData($tMode, 2)
	Return $sMapname
EndFunc


Func GetPlayerName($iPlayer)
	Local $tMode = DllStructCreate("ptr;wchar[32]")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0x109B628") + Ptr(0x3C * ($iPlayer-1))
	Local $sPlayername, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1)

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 2), 32, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$sPlayername = DllStructGetData($tMode, 2)
	Return $sPlayername
EndFunc

Func GetPlayerCount()
	Local $pPlayerCountAddress = $__pThreadBaseAddress + Ptr("0xE94828")
	Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPlayerCountAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc

Func GetCurrentPlayer()
	Local $pPlayerAddress = $__pThreadBaseAddress + Ptr("0xE9482C")
	Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPlayerAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc

Func GetElapsedGameTime()
	Local $iTicks = GetTicks()
	If @error Then Return SetError(1, 0, False)

	Local $iSeconds, $iMinutes, $iHours, $sFormattedString

	$iSeconds = $iTicks * 0.071	; Null Ahnung warum dieser Wert... aber Kevin hats gecheckt! :-)
	$iMinutes = Floor($iSeconds / 60)
	$iHours   = Floor($iMinutes / 60)
	$iMinutes = Floor(Mod($iMinutes, 60))
	$iSeconds = Floor(Mod($iSeconds, 60))

	$sFormattedString = StringFormat("%02d:%02d:%02d", $iHours, $iMinutes, $iSeconds)
	Return $sFormattedString
EndFunc


Func GetThreadBaseAddress($hProcess, $iProcessID)
	If Not ProcessExists($iProcessID) Then Return SetError(1, 0, False)

	; Basisadresse des Spiels extrahieren
	Local $pThreadAddress =_MemoryModuleGetBaseAddress($iProcessID, "S4_Main.exe")
	If @error Then Return SetError(2, 0, False)

	ConsoleWrite("Adresse der S4_Main.exe: " & $pThreadAddress & @CRLF)

	$__pThreadBaseAddress = $pThreadAddress
	Return True
EndFunc


Func GetPlayerBaseAddresses($hProcess, $iProcessID)
	If Not ProcessExists($iProcessID) Then Return SetError(1, 0, False)

	Local $tMode = DllStructCreate("ptr")
	Local Const $hOffset = "0x000F8ED4"
 	Local Const $iBaseOffset = -536
	Local $iBytesRead = 0

	; Hole Static Pointer auf die aktuelle Turmanzahl (kleine Türme) von Spieler 1
	Local $bSuccess = _WinAPI_ReadProcessMemory($hProcess, $__pThreadBaseAddress+$hOffset, DLLStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then SetError(3, 0, False)

	ConsoleWrite("Basisadresse: " & DllStructGetData($tMode, 1) & @CRLF)
	Local $pBaseAddress = DllStructGetData($tMode, 1)

	; Offsets der Spieler berechnen
	For $i = 1 To 8
		Local $iPlayerOffset = ($i-1) * 4392
		$__pPlayerBase[$i-1] = $pBaseAddress + $iBaseOffset + $iPlayerOffset
		ConsoleWrite("Spieler " & $i & " Basisadresse: " & $__pPlayerBase[$i-1] & @CRLF)
	Next

	Return True
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

Func IsMatchRunning()
	If GetTicks() > 0 Then Return True
	Return False
EndFunc

Func GetPlayerData($iPlayer, $iOffset)
	If $__pPlayerBase[$iPlayer-1] = Null Then Return SetError(1, 0, False)

	Local $tMode = DllStructCreate("int")
	Local $pMode = DllStructGetPtr($tMode, 1)

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $__pPlayerBase[$iPlayer-1] + $iOffset, $pMode, 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & "::" & _WinAPI_GetLastErrorMessage(), False)

	;ConsoleWrite("Spieler " & $iPlayer & " Offset: " & $iOffset & ", Daten: " & DllStructGetData($tMode, 3) & @CRLF)
	Return DllStructGetData($tMode, 1)
EndFunc

Func GetPlayerDataEx($iPlayer, ByRef $aData)
	Const $iValues = 1049
	If $__pPlayerBase[$iPlayer-1] = Null Then Return SetError(1, 0, False)

	Local $tMode = DllStructCreate("int[" & $iValues & "]")
	Local $pMode = DllStructGetPtr($tMode, 1)

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $__pPlayerBase[$iPlayer-1], $pMode, $iValues*4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & "::" & _WinAPI_GetLastErrorMessage(), False)

	ReDim $aData[$iValues]
	For $i = 1 To $iValues
		$aData[$i-1] = DllStructGetData($tMode, 1, $i)
	Next
EndFunc

Func GetOffsetData()
	_FileReadToArray($sFileIn, $__aOffsetList, $FRTA_COUNT, @TAB)
EndFunc

Func LogFileOpen()
	$__iLineCounter = 0

	Local $sNow = _Now()
	$sNow = StringReplace($sNow, "/", "-")
	$sNow = StringReplace($sNow, "\", "-")
	$sNow = StringReplace($sNow, ".", "-")
	$sNow = StringReplace($sNow, ":", "-")
	$sNow = StringReplace($sNow, " ", "_")

	Local $sFileName = StringReplace($sFileOut, "%NOW%", $sNow)

	$__fHnd = FileOpen($sFileName, $FO_APPEND)

	; Header mit Spieleranzahl und Spielernamen
	Local $iPlayerCount = GetPlayerCount()
	Local $sHeader = GetMapName() & @TAB & String($iPlayerCount) & @TAB

	For $i = 1 To $iPlayerCount
		$sHeader = $sHeader & GetPlayerName($i) & @TAB
	Next

	FileWriteLine($__fHnd, $sHeader)

	; Headline mit Bezeichnungen der Datenzeilen
	Local $sHeadline = "Zeitstempel" & @TAB & "Zähler" & @TAB & "Spieler" & @TAB

	For $i = 1 To $__aOffsetList[0][0]
		$sHeadline = $sHeadline & $__aOffsetList[$i][2] & " - " & $__aOffsetList[$i][1] & @TAB
	Next

	FileWriteLine($__fHnd, $sHeadline)
EndFunc

Func LogFileClose()
	FileClose($__fHnd)
	$__fHnd = Null
EndFunc

Func LogData()
	If $__fHnd = Null Then Return False

	Local $sNewLine
	Local $iPlayerCount = GetPlayerCount()
	Local $aPlayerData[0]

	For $iPlayer = 1 To $iPlayerCount ; Könnte buggy sein, falls ein Spieler aussteigt und sich dieser Wert ändert
		If GUICtrlRead($__aCheckbox[$iPlayer-1]) = $GUI_CHECKED Then
			$__iLineCounter = $__iLineCounter + 1
			$sNewLine = ($bUseRealtime ? _Now() : GetElapsedGameTime()) & @TAB & $__iLineCounter & @TAB & $iPlayer & @TAB

			#cs
			; Alte Funktion holt die Daten einzeln, ist okay aber nicht sehr performant
			For $i = 1 To $__aOffsetList[0][0]
				$sNewLine = $sNewLine & GetPlayerData($iPlayer, $__aOffsetList[$i][0]) & @TAB
			Next
			#ce

			; Neue Funktion holt alle Daten auf einmal in ein Array
			GetPlayerDataEx($iPlayer, $aPlayerData)
			For $i = 1 To $__aOffsetList[0][0]
				$sNewLine = $sNewLine & $aPlayerData[$__aOffsetList[$i][0] / 4] & @TAB
			Next

			; Letztes Trennzeichen entfernen
			$sNewLine = StringTrimRight($sNewLine, 1)

			;ConsoleWrite($sNewLine & @CRLF)
			FileWriteLine($__fHnd, $sNewLine)
		EndIf
	Next
EndFunc


Func ToggleLogging()
	If $__bLoggingEnabled Then
		DisableLogging()
	Else
		EnableLogging()
	EndIf
EndFunc

Func EnableLogging()
	$__bLoggingEnabled = True
	GUICtrlSetData($__Label4, "Aktiv")

	For $i = 0 To 7
		GUICtrlSetStyle($__aCheckbox[$i], BitOR($BS_AUTOCHECKBOX, $WS_DISABLED))
	Next

	;TrayTip("Siedler IV Statlogger", "Logging aktiviert", 10, $TIP_ICONASTERISK)
EndFunc

Func DisableLogging()
	$__bLoggingEnabled = False
	FileFlush($__fHnd)
	GUICtrlSetData($__Label4, "Inaktiv")

	For $i = 0 To 7
		GUICtrlSetStyle($__aCheckbox[$i], $BS_AUTOCHECKBOX)
	Next

	;TrayTip("Siedler IV Statlogger", "Logging deaktiviert", 10, $TIP_ICONASTERISK)
EndFunc

Func CloseButton()
	LogFileClose()
	CloseProcess()
	Exit 0
EndFunc