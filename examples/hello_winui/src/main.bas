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

CALL WinUIHostClose(host)
PRINT "Host closed. Round trip OK."
