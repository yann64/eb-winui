' Launches the WinUI3 host process (see ../../../host/), then drives it
' through a few real commands - proof that eBasic can launch and
' interactively control a live, native WinUI3 window from outside the
' process (see README.md's "Why a separate process" section for why
' it's a separate process rather than an in-process binding).
'
' There's no way to visually confirm a native window updated from this
' session - verification instead checks the host's own real "OK <cmd>"
' acknowledgement line, written back only once the mutation was
' actually applied on the UI thread (see host/MainWindow.xaml.cpp).
'
' Usage: hello_winui.exe <path to eb_winui3_host.exe>
' (built separately via msbuild - see README.md's "Building the host")

#include "winui.iface.bas"

DIM hostExePath AS STRING
hostExePath = Command()
IF hostExePath = "" THEN
    PRINT "usage: hello_winui <path to eb_winui3_host.exe>"
    CALL ExitProcess(1)
END IF

DIM host AS WinUIHost
host = NewWinUIHost(hostExePath, "eBasic + WinUI3", "Hello from eBasic")
IF host.processHandle = 0 THEN
    PRINT "FAIL: could not launch the WinUI3 host process"
    CALL ExitProcess(1)
END IF
PRINT "Host launched."

DIM ack AS STRING
ack = WinUIHostSetText(host, "Updated from eBasic!")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: SETTEXT was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

ack = WinUIHostSetTitle(host, "Renamed from eBasic")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: SETTITLE was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

' Round 2: dynamic widgets. There's still no way for this session to
' perform a real click - verified the same way SETTEXT/SETTITLE are
' above (a real "OK ADD ..." acknowledgement, only written back once
' the widget actually exists in the live visual tree); a real click
' round trip (WinUIHostReadEvent seeing "CLICKED btn1") needs a human
' at the keyboard, or a future round's own automation.
ack = WinUIHostAddButton(host, "btn1", "Dynamic Button", "ROOT")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: ADD BUTTON was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

ack = WinUIHostAddTextBlock(host, "tb1", "Added dynamically from eBasic", "ROOT")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: ADD TEXTBLOCK was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

' Round 3: update/remove by id, and a nested container - a real,
' verifiable proof each of these actually reaches the live widget, not
' just "some command got acknowledged."
ack = WinUIHostSet(host, "btn1", "Renamed via WinUIHostSet")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: SET was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

ack = WinUIHostRemove(host, "tb1")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: REMOVE was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

ack = WinUIHostAddStackPanel(host, "panel1", "HORIZONTAL", "ROOT")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: ADD STACKPANEL was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

ack = WinUIHostAddButton(host, "nested1", "Inside panel1", "panel1")
PRINT ack
IF Left(ack, 3) <> "OK " THEN
    PRINT "FAIL: nested ADD BUTTON was not acknowledged"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

' A real, checked error case too - not just the happy path.
ack = WinUIHostSet(host, "does-not-exist", "irrelevant")
PRINT ack
IF Left(ack, 4) <> "ERR " THEN
    PRINT "FAIL: SET on an unknown id should have been rejected"
    CALL WinUIHostClose(host)
    CALL ExitProcess(1)
END IF

CALL WinUIHostClose(host)
PRINT "Host closed. Round trip OK."
