#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_UseX64=n
#AutoIt3Wrapper_Res_Language=3079
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
#cs ----------------------------------------------------------------------------

 AutoIt Version: 3.3.14.5
 Author:
	Alex 'Monoxid' W.
	Kevin 'DJDeagle' M.

 Licence:
   The Settlers IV-Logger (c) by Alex 'Monoxid' W. and Kevin 'DJDeagle' M.

   The Settlers IV-Logger is licensed under a
   Creative Commons Attribution-ShareAlike 4.0 International License.

    You should have received a copy of the license along with this
    work. If not, see <http://creativecommons.org/licenses/by-sa/4.0/>.

 Script Function:
	Loggt Werte definiert in einer CSV aus einer laufenden Die Siedler IV Partie
	in ein CSV File

 Licence: (https://creativecommons.org/licenses/by-nc-sa/4.0/)
	This code has ben released under the CC-BY-SA licence.

 Website: https://www.elektronikundco.de/

 Git: https://www.github.com/linglingltd/siedleriv-logger

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

	V4: Spielerfarbe, Team, Rasse und Teilnahmestatus können nun ausgelesen werden
		Anpassung der Benutzeroberfläche

#ce ----------------------------------------------------------------------------

#include <Array.au3>
#include <ColorConstants.au3>
#include <Date.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <FontConstants.au3>
#include <GUIConstants.au3>
#include <GUIConstantsEx.au3>
#include <ProcessConstants.au3>
#include <TrayConstants.au3>
#include <WinAPIProc.au3>
#include <WinAPIMem.au3>
#include <WinAPIHObj.au3>
#include <WinAPIError.au3>
#include <WindowsConstants.au3>

Opt('MustDeclareVars', 1)
Opt("GUIOnEventMode",  1)

; Konfiguration laden
Global $iLogInterval = Int(IniRead("settings.ini", "Logger", "LogInterval", "5000"))
Global $sFileIn = IniRead("settings.ini", "Input", "File", "list.csv")
Global $sFileOut = IniRead("settings.ini", "Output", "File", "logs/sivlog%NOW%.csv")
Global $sSeparator = IniRead("settings.ini", "Output", "Separator", ";")							; Trennzeichen für Outputdatei
Global $bShowRace = Int(IniRead("settings.ini", "General", "ShowRace", "0")) ? True : False			; Rassen im Logger anzeigen oder nicht (Spoiler)

Global $__VERSION = "4"

Global $__iProcessID = -1, $__hProcess = Null
Global $__pPlayerBase[8] = [Null,Null,Null,Null,Null,Null,Null,Null], $__pThreadBaseAddress = Null, $__pTickAddress = Null
Global $__fHnd = Null, $__aOffsetList

Global $__aPlayerLabel[8], $__Edit1, $__Label1, $__Label2, $__Label3, $__Label4, $__Label5, $__Label6, $__Label7, $__ListView, $__ListViewItems[3]

Global $__bLoggingEnabled = True, $__bMatchInitialized = False
Global $__iLineCounter = 0

Global $aPlayerAlive[8] = [True, True, True, True, True, True, True, True]

; Hauptfunktion, erzeugt grafische Oberfläche und prüft auf Spielparameter
Func Main()
	If Not GetOffsetData() Then Return

	Local $hWinMain = GUICreate("SIV Logger " & $__VERSION, 362, 460)
	GUISetFont(Default, Default, Default, "Consolas")

	$__Label1 = GUICtrlCreateLabel("Spielerinformationen:", 8, 8, 346, 20)
	GUICtrlSetFont(-1, 11, $FW_SEMIBOLD)

	$__Label2 = GUICtrlCreateLabel("Name                              Rasse     Team   Farbe", 8, 25, 442, 16)
	GUICtrlSetFont(-1, Default, Default, $GUI_FONTUNDER)

	For $i = 0 To 7
		$__aPlayerLabel[$i] = GUICtrlCreateLabel("Spieler " & $i+1, 8, 40 + 16 * $i, 442, 16)
		GUICtrlSetColor(-1, $COLOR_BLACK)
	Next

	$__Label3 = GUICtrlCreateLabel("Spielinformationen:", 8, 175, 346, 20)
	GUICtrlSetFont(-1, 11, $FW_SEMIBOLD)

	$__Label4 = GUICtrlCreateLabel("Programminformationen:", 8, 305, 346, 20)
	GUICtrlSetFont(-1, 11, $FW_SEMIBOLD)

	$__Label5 = GUICtrlCreateLabel("Logging ist:", 8, 430, 120, 20, $SS_CENTERIMAGE)
	GUICtrlSetFont(-1, 12)

	$__Label6 = GUICtrlCreateLabel("Inaktiv", 120, 430, 85, 20, $SS_CENTERIMAGE)
	GUICtrlSetFont(-1, 14)

	$__Label7 = GUICtrlCreateLabel("www.elektronikundco.de", 220, 440, 135, 15)
	GUICtrlSetFont(-1, Default, Default, $GUI_FONTUNDER)
	GUICtrlSetColor(-1, $COLOR_BLUE)

	$__Edit1 = GUICtrlCreateEdit("Warte auf Spielstart", 8, 325, 346, 100, BitOR($ES_WANTRETURN, $WS_VSCROLL, $ES_AUTOVSCROLL, $ES_READONLY))

	$__ListView = GUICtrlCreateListView("Name                          |Wert                          ", 8, 195, 346, 100)

	$__ListViewItems[0] = GUICtrlCreateListViewItem("Karte|",		  $__ListView)
	$__ListViewItems[1] = GUICtrlCreateListViewItem("Spieleranzahl|", $__ListView)
	$__ListViewItems[2] = GUICtrlCreateListViewItem("Spielzeit|",	  $__ListView)

	GUISetOnEvent($GUI_EVENT_CLOSE, "CloseButton")
	GUICtrlSetOnEvent($__Label7, "OpenLink")
	GUISetState(@SW_SHOW)

	Local $bMatchRunningInfo = False
	Local $hLogTimerHandle = TimerInit()

	While 1
		; Prozess öffnen
		If $__hProcess == Null Then
			If OpenProcess() Then
				GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Spiel gestartet" & @CRLF & "Warte auf Partiestart")
			EndIf
		Else
			; Das Spiel wurde beendet
			If Not ProcessExists($__iProcessID) Then
				DisableLogging()
				LogFileClose()
				CloseProcess()
				GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Spiel beendet")
			Else
				; Es läuft bereits eine Partie
				If IsMatchRunning() Then
					GUICtrlSetData($__ListViewItems[2], "Spielzeit|" & GetElapsedGameTime())

					; Die Partie einmalig im Logger initialisieren
					If Not $__bMatchInitialized Then
						$__bMatchInitialized = True

						GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Partie gestartet")

						; Header für Debug Output
						ConsoleWrite("Name                              Rasse     Team   Farbe" & @CRLF)
						Local $iPlayerCount = GetPlayerCount()

						For $i = 1 To $iPlayerCount
							Local $sPlayerString = StringFormat("%-32s  %-8s  %-4s   %-6s", GetPlayerName($i), ($bShowRace ? GetRaceName(GetPlayerRace($i)) : "-"), GetTeamString(GetPlayerTeam($i)), GetColorName(GetPlayerColor($i)))
							GUICtrlSetData($__aPlayerLabel[$i-1], $sPlayerString)

							; Farbe der Spieler einstellen - ist tw. unlesbar, daher inaktiv
							;GUICtrlSetColor($__aPlayerLabel[$i-1], Dec(GetPlayerColor($i)))

							; Teilnahmestatus zurücksetzen
							$aPlayerAlive[$i-1] = True

							; Debug Output für alle Spieler
							ConsoleWrite($sPlayerString & @CRLF)
						Next

						; Alle unbelegten Spielerplätze ausblenden
						If $iPlayerCount < 8 Then
							For $i = ($iPlayerCount + 1) To 8
								GUICtrlSetData($__aPlayerLabel[$i-1], "")
								$aPlayerAlive[$i-1] = False
							Next
						EndIf

						GUICtrlSetData($__ListViewItems[0], "Karte|" & GetMapName())
						GUICtrlSetData($__ListViewItems[1], "Spieleranzahl|" & GetPlayerCount())
						GUICtrlSetData($__ListViewItems[2], "Spielzeit|" & GetElapsedGameTime())

						LogFileOpen()
						EnableLogging()
					EndIf


					; Mitspielstatus prüfen
					Local $iPlayerCount = GetPlayerCount()
					For $i = 1 To $iPlayerCount
						If $aPlayerAlive[$i-1] = True And Not IsPlayerAlive($i) Then
							$aPlayerAlive[$i-1] = False
							GUICtrlSetColor($__aPlayerLabel[$i-1], $COLOR_GRAY)
							;GUICtrlSetFont($__aPlayerLabel[$i-1], Default, Default, $GUI_FONTSTRIKE)
							GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & GetPlayerName($i) & " ist ausgeschieden")

							; Sieg überprüfen
							Local $iTeamWin = -1
							For $j = 1 To $iPlayerCount
								If IsPlayerAlive($j) Then
									Local $iTeam = GetPlayerTeam($j)
									If $iTeamWin = -1 Or $iTeamWin = $iTeam Then
										; Mögliches Gewinnerteam ablegen
										$iTeamWin = $iTeam
									Else
										; Es gibt noch keinen Gewinner
										$iTeamWin = -1
										ExitLoop
									EndIf
								EndIf
							Next

							If $iTeamWin <> -1 Then
								GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Team " & GetTeamString($iTeamWin) & " hat gewonnen!")
							EndIf
						EndIf
					Next

					; Daten loggen
					If $__bLoggingEnabled AND TimerDiff($hLogTimerHandle) > $iLogInterval Then
						$hLogTimerHandle = TimerInit()
						LogData()
					EndIf

				; Es läuft keine Partie
				Else
					; Es war eine Partie initialisiert, daher ist sie nun beendet
					If $__bMatchInitialized = True Then
						$__bMatchInitialized = False

						GUICtrlSetData($__Edit1, GUICtrlRead($__Edit1) & @CRLF & "Partie beendet")

						GUICtrlSetData($__ListViewItems[0], "Karte|")
						GUICtrlSetData($__ListViewItems[1], "Spieleranzahl|")
						GUICtrlSetData($__ListViewItems[2], "Spielzeit|")

						DisableLogging()
						LogFileClose()

						For $i = 1 To 8
							GUICtrlSetData($__aPlayerLabel[$i-1], "Spieler " & $i)
							GUICtrlSetColor($__aPlayerLabel[$i-1], $COLOR_BLACK)
							GUICtrlSetFont($__aPlayerLabel[$i-1], Default, Default, $GUI_FONTNORMAL)
						Next
					EndIf
				EndIf
			EndIf
		EndIf

		Sleep(500)
	WEnd
EndFunc

; Öffnet den Siedler IV Prozess
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

; Schließt den Siedler IV Handle
Func CloseProcess()
	_WinAPI_CloseHandle($__hProcess)
	$__hProcess = Null
EndFunc

; Gibt die verstrichenen Ticks im Spiel zurück
Func GetTicks()
	Static Local $pTicksAddress = $__pThreadBaseAddress + Ptr("0xE66B14")
	Static Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pTicksAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & "::" & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc

; Gibt den Kartennamen aus dem Spiel zurück - Funktioniert nicht bei Szenario oder speziellen Mapdateien!
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

; Gibt das Team des Spielers als Zahl zurück
Func GetPlayerTeam($iPlayer)
	Local $tMode = DllStructCreate("ptr;int")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0xFE748")
	Local $sPlayername, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1) + Ptr(4 * ($iPlayer-1))

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 2), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Local $iPlayerTeam = Int(DllStructGetData($tMode, 2))
	Return $iPlayerTeam
EndFunc

; Formatiert einen Teamwert in eine römische Zahl
Func GetTeamString($iTeam)
	Local $sTeamStrings = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
	Return $sTeamStrings[$iTeam-1]
EndFunc

; Prüft, ob ein Spieler noch aktiv an der Partie teilnimmt
Func IsPlayerAlive($iPlayer)
	Local $tMode = DllStructCreate("ptr;int")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0xF86E8")
	Local $sPlayername, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1) + 52 + Ptr(60 * ($iPlayer-1))

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 2), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Local $iPlayerAlive = Int(DllStructGetData($tMode, 2))
	If $iPlayerAlive == 1 Then
		Return True
	Else
		Return False
	EndIf
EndFunc

; Gibt die gespielte Rasse eines Spielers zurück
Func GetPlayerRace($iPlayer)
	Local $tMode = DllStructCreate("ptr;int")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0xF86E8")
	Local $sPlayername, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1) + Ptr(60 * ($iPlayer-1))

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 2), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Local $iPlayerRace = Int(DllStructGetData($tMode, 2))
	Return $iPlayerRace
EndFunc

; Gibt einen Namen zu einem Rassenwert zurück
Func GetRaceName($iRace)
	Switch $iRace
		Case 0
			Return "Römer"
		Case 1
			Return "Wikinger"
		Case 2
			Return "Maya"
		Case 3
			Return "Dunkles Volk?"	; Nicht überprüft
		Case 4
			Return "Trojaner"
		Case Else
			Return "Lemminge"		; Fehlerfall
	EndSwitch
EndFunc

; Gibt die Spielerfarbe als HEXcode (RRGGBB) zurück
Func GetPlayerColor($iPlayer)
	Local $tMode = DllStructCreate("ptr;int;int;int")
	Local $pPointer = $__pThreadBaseAddress + Ptr("0xFE748")
	Local $iColorOffset = -128
	Local $sPlayername, $iBytesRead = 0

	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(1, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$pPointer = DllStructGetData($tMode, 1) + $iColorOffset + Ptr(12 * ($iPlayer-1))

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer + 0, DllStructGetPtr($tMode, 2), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer + 4, DllStructGetPtr($tMode, 3), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	$bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPointer + 8, DllStructGetPtr($tMode, 4), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Local $iPlayerColorRed		= Int(DllStructGetData($tMode, 2))
	Local $sPlayerColorGreen	= Int(DllStructGetData($tMode, 3))
	Local $sPlayerColorBlue		= Int(DllStructGetData($tMode, 4))

	Local $sHexValue = Hex(BitOR(BitShift($iPlayerColorRed, -16), BitShift($sPlayerColorGreen, -8), $sPlayerColorBlue), 6)
	Return $sHexValue
EndFunc

; Gibt den Farbnamen zu einem HEXcode einer Farbe zurück
Func GetColorName($iColorCode)
	Local $aColorNames = ["Rot", "Blau", "Grün", "Gelb", "Lila", "Orange", "Cyan", "Weiß"]

	Switch $iColorCode
		Case "F01515" ; Rot
			Return $aColorNames[0]
		Case "453ED2" ; Blau
			Return $aColorNames[1]
		Case "00C836" ; Grün
			Return $aColorNames[2]
		Case "FAEE00" ; Gelb
			Return $aColorNames[3]
		Case "BE4BFF" ; Lila
			Return $aColorNames[4]
		Case "FDA024" ; Orange
			Return $aColorNames[5]
		Case "21C5B5" ; Cyan
			Return $aColorNames[6]
		Case "E6FFFF" ; Weiß
			Return $aColorNames[7]
		Case Else ; Fehler in der Matrix
			Return "Unbekannt"
	EndSwitch

	Return $aColorNames[$iColorCode]
EndFunc

; Gibt den Spielernamen zurück
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

; Gibt die Anzahl der an der Partie teilnehmenden Spieler (inkl. KI) zurück
Func GetPlayerCount()
	Local $pPlayerCountAddress = $__pThreadBaseAddress + Ptr("0xE94828")
	Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPlayerCountAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc

; Gibt die Nummer des eigenen Spielers zurück
Func GetCurrentPlayer()
	Local $pPlayerAddress = $__pThreadBaseAddress + Ptr("0xE9482C")
	Local $tMode = DllStructCreate("int")

	Local $iBytesRead = 0
	Local $bSuccess = _WinAPI_ReadProcessMemory($__hProcess, $pPlayerAddress, DllStructGetPtr($tMode, 1), 4, $iBytesRead)
	If Not $bSuccess Then Return SetError(2, _WinAPI_GetLastError() & " :: " & _WinAPI_GetLastErrorMessage(), False)

	Return DllStructGetData($tMode, 1)
EndFunc

; Gibt die verstrichene Spielzeit zurück
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

; Gibt die Basisadresse des S4_Main Threads zurück
Func GetThreadBaseAddress($hProcess, $iProcessID)
	If Not ProcessExists($iProcessID) Then Return SetError(1, 0, False)

	; Basisadresse des Spiels extrahieren
	Local $pThreadAddress =_MemoryModuleGetBaseAddress($iProcessID, "S4_Main.exe")
	If @error Then Return SetError(2, 0, False)

	ConsoleWrite("Adresse der S4_Main.exe: " & $pThreadAddress & @CRLF)

	$__pThreadBaseAddress = $pThreadAddress
	Return True
EndFunc

; Berechnet die Basisadressen aller Spieler
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

; Gibt den aktuellen Partiestatus zurück
Func IsMatchRunning()
	If GetTicks() > 0 Then Return True
	Return False
EndFunc

; Gibt Spieldaten von gegebenem Spieler an gegebenem Offset zurück
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

; Holt einen Großteil der Spielerdaten aus dem RAM
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

; Liest die Offsetdaten aus dem Inputfile in ein Array ein
Func GetOffsetData()
	If Not FileExists($sFileIn) Then
		MsgBox(BitOR($MB_ICONERROR, $MB_ICONERROR), "SIV Logger " & $__VERSION, "Fehler!" & @CRLF & "Datei '" & $sFileIn & "' wurde nicht gefunden.")
		Return False
	EndIf

	_FileReadToArray($sFileIn, $__aOffsetList, $FRTA_COUNT, @TAB)
	Return True
EndFunc

; Öffnet ein Logfile und schreibt die Kopfdaten
Func LogFileOpen()
	$__iLineCounter = 0

	Local $sNow = @YEAR & "-" & @MON & "-" & @MDAY & "_" & @HOUR & "-" & @MIN

	Local $sFileName = StringReplace($sFileOut, "%NOW%", $sNow)
	$sFileName = StringReplace($sFileName, "%USERNAME%", @UserName)

	$__fHnd = FileOpen($sFileName, BitOR($FO_APPEND,  $FO_CREATEPATH))

	; Kopfdaten mit Kartenname und Spieleranzahl
	Local $iPlayerCount = GetPlayerCount()
	Local $sHeader = GetMapName() & $sSeparator & String($iPlayerCount)
	FileWriteLine($__fHnd, $sHeader)

	; Spielernamen
	Local $sLine = ""
	For $i = 1 To $iPlayerCount
		$sLine = GetPlayerName($i) & $sSeparator & GetRaceName(GetPlayerRace($i)) & $sSeparator & GetPlayerColor($i) & $sSeparator & GetPlayerTeam($i)
		FileWriteLine($__fHnd, $sLine)
	Next

	; Überschrift mit Bezeichnungen der Datenzeilen
	Local $sHeadline = "Zeitstempel" & $sSeparator & "Zähler" & $sSeparator & "Spieler" & $sSeparator & "Aktiv" & $sSeparator

	For $i = 1 To $__aOffsetList[0][0]
		$sHeadline = $sHeadline & $__aOffsetList[$i][2] & " - " & $__aOffsetList[$i][1] & $sSeparator
	Next

	FileWriteLine($__fHnd, $sHeadline)
EndFunc

; Schließt die Logdatei
Func LogFileClose()
	FileClose($__fHnd)
	$__fHnd = Null
EndFunc

; Loggt aktuelle Spieldaten
Func LogData()
	If $__fHnd = Null Then Return False

	Local $sNewLine
	Local $iPlayerCount = GetPlayerCount()
	Local $aPlayerData[0]

	For $iPlayer = 1 To $iPlayerCount ; Könnte buggy sein, falls ein Spieler aussteigt und sich dieser Wert ändert
		$__iLineCounter = $__iLineCounter + 1
		$sNewLine = GetElapsedGameTime() & $sSeparator & _
		$__iLineCounter & $sSeparator & _
		$iPlayer & $sSeparator & _
		(IsPlayerAlive($iPlayer) ? "1" : "0") & $sSeparator

		#cs
		; Alte Funktion holt die Daten einzeln, ist okay aber nicht sehr performant
		For $i = 1 To $__aOffsetList[0][0]
			$sNewLine = $sNewLine & GetPlayerData($iPlayer, $__aOffsetList[$i][0]) & @TAB
		Next
		#ce

		; Neue Funktion holt alle Daten auf einmal in ein Array
		GetPlayerDataEx($iPlayer, $aPlayerData)
		For $i = 1 To $__aOffsetList[0][0]
			$sNewLine = $sNewLine & $aPlayerData[$__aOffsetList[$i][0] / 4] & $sSeparator
		Next

		; Letztes Trennzeichen entfernen
		$sNewLine = StringTrimRight($sNewLine, StringLen($sSeparator))

		;ConsoleWrite($sNewLine & @CRLF)
		FileWriteLine($__fHnd, $sNewLine)
	Next
EndFunc

; Logging ein/ausschalten
Func ToggleLogging()
	If $__bLoggingEnabled Then
		DisableLogging()
	Else
		EnableLogging()
	EndIf
EndFunc

; Logging aktivieren
Func EnableLogging()
	$__bLoggingEnabled = True
	GUICtrlSetData($__Label6, "Aktiv")
EndFunc

; Logging deaktivieren
Func DisableLogging()
	$__bLoggingEnabled = False
	FileFlush($__fHnd)
	GUICtrlSetData($__Label6, "Inaktiv")
EndFunc

; Öffnet den Link zu einer sehr tollen Internetseite
Func OpenLink()
	ShellExecute("https://www.elektronikundco.de/")
EndFunc

; Gibt alle Ressourcen frei und beendet das Programm
Func CloseButton()
	LogFileClose()
	CloseProcess()
	Exit 0
EndFunc


; Programm starten
Main()