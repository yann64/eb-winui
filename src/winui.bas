' Idiomatic layer: launches a WinUI3 host process (see host/ - a
' separate, real C++/WinRT/XAML executable, built with msbuild, not by
' ebc) with its stdin/stdout redirected through anonymous pipes, and
' talks to it over a simple line-based text protocol - one command per
' line in (SETTEXT/SETTITLE/QUIT), one acknowledgement line back
' ("OK <command>", or "ERR ..." for an unrecognized command). See
' README.md's "Why a separate process" section for why this isn't an
' in-process binding.

#include once "raw/win32_process.bas"

TYPE WinUIHost
    processHandle AS ANY PTR
    hStdInWrite AS ANY PTR
    hStdOutRead AS ANY PTR
END TYPE

' A ZSTRING return value (needed at every --lib-exported boundary -
' STRING itself isn't exportable, see extern-interop.md) is only valid
' as long as whatever STRING backs it is still alive; a function-local
' STRING doesn't survive past `return`, so every ZSTRING-returning
' function below copies its result into this single, persistent,
' module-level buffer first and returns a view of *that* - safe because
' the caller's own STRING assignment (`ack = WinUIHostSetText(...)`)
' copies the characters out immediately, before this buffer's next
' overwrite on the following call (this package's own protocol is
' strictly one request/one response at a time, never concurrent).
DIM winuiScratch AS STRING

' HANDLE_FLAG_INHERIT
CONST WinUIHandleFlagInherit AS UINTEGER = 1
' STARTF_USESTDHANDLES
CONST WinUIStartfUseStdHandles AS UINTEGER = 256

''' Wraps a value in double quotes for CreateProcessA's own
''' space-separated argv parsing - `hostExePath`/`title`/`message` are
''' each passed through this. Accepted limitation for this first round:
''' no escaping for an embedded `"` in any of the three - matches this
''' package's own "surfaces as a real, documented gap rather than
''' silently mishandled" convention (see eb-win32's PTR-upcast note).
FUNCTION WinUIQuoteArg(BYVAL s AS STRING) AS STRING
    WinUIQuoteArg = Chr(34) & s & Chr(34)
END FUNCTION

''' Blocks until one full line (up to, not including, the terminating
''' `Chr(10)`) is available from the host's stdout pipe - `""` if the
''' pipe closed (the host process exited) before a newline arrived.
''' Reads one byte at a time: this is a low-volume control channel
''' (one short acknowledgement line per command), not a data-transfer
''' path, so the extra ReadFile calls this costs are not a real concern.
''' Internal (STRING isn't --lib-exportable - see WinUIHostReadEvent,
''' the public ZSTRING-returning wrapper around this).
FUNCTION WinUIReadLine(h AS WinUIHost) AS STRING
    DIM line AS STRING
    DIM one AS UBYTE
    DIM bytesRead AS UINTEGER
    DIM ok AS INTEGER
    line = ""
    DO
        ok = Win32ReadFile(h.hStdOutRead, @one, 1, @bytesRead, 0)
        IF ok = 0 OR bytesRead = 0 THEN
            EXIT DO
        END IF
        IF one = 10 THEN
            EXIT DO
        END IF
        IF one <> 13 THEN
            line = line & Chr(one)
        END IF
    LOOP
    WinUIReadLine = line
END FUNCTION

SUB WinUIHostSendCommand(h AS WinUIHost, BYVAL cmd AS STRING)
    DIM line AS STRING
    DIM bytesWritten AS UINTEGER
    line = cmd & Chr(10)
    CALL Win32WriteFile(h.hStdInWrite, line, Len(line), @bytesWritten, 0)
END SUB

''' Launches `hostExePath` (the built host/eb_winui3_host.exe - see
''' README.md's "Building the host" section) with `title`/`message` as
''' its initial window title/text, pipes fully connected. `.processHandle`
''' is 0 if CreateProcessA itself failed (check before using - matches
''' eb-win32's own no-exceptions, check-the-handle convention throughout).
FUNCTION NewWinUIHost(hostExePath AS ZSTRING, title AS ZSTRING, message AS ZSTRING) AS WinUIHost
    DIM h AS WinUIHost

    DIM sa AS Win32SecurityAttributes
    sa.nLength = 24
    sa.lpSecurityDescriptor = 0
    sa.bInheritHandle = 1

    DIM childStdinRead AS ANY PTR
    DIM childStdinWrite AS ANY PTR
    DIM childStdoutRead AS ANY PTR
    DIM childStdoutWrite AS ANY PTR

    IF CreatePipe(@childStdinRead, @childStdinWrite, @sa, 0) = 0 THEN
        h.processHandle = 0
        NewWinUIHost = h
        EXIT FUNCTION
    END IF
    IF CreatePipe(@childStdoutRead, @childStdoutWrite, @sa, 0) = 0 THEN
        CALL CloseHandle(childStdinRead)
        CALL CloseHandle(childStdinWrite)
        h.processHandle = 0
        NewWinUIHost = h
        EXIT FUNCTION
    END IF

    ' Both ends of each pipe came back inheritable (sa.bInheritHandle
    ' was needed so the CHILD's own ends are); un-inherit the two ends
    ' THIS process is keeping, or the child's own inherited copy of
    ' them would keep those pipes half-open after the child exits.
    CALL SetHandleInformation(childStdinWrite, WinUIHandleFlagInherit, 0)
    CALL SetHandleInformation(childStdoutRead, WinUIHandleFlagInherit, 0)

    DIM si AS Win32StartupInfoA
    si.cb = 104
    si.dwFlags = WinUIStartfUseStdHandles
    si.hStdInput = childStdinRead
    si.hStdOutput = childStdoutWrite
    si.hStdError = childStdoutWrite

    DIM cmdLine AS STRING
    cmdLine = WinUIQuoteArg(hostExePath) & " " & WinUIQuoteArg(title) & " " & WinUIQuoteArg(message)

    DIM pi AS Win32ProcessInformation
    DIM started AS INTEGER
    started = CreateProcessA(0, cmdLine, 0, 0, 1, 0, 0, 0, @si, @pi)

    ' Whether or not the launch succeeded, the child's own ends of both
    ' pipes are no longer needed on this side - it has its own inherited
    ' copies (on success), and there's nothing to close them for on
    ' failure either way.
    CALL CloseHandle(childStdinRead)
    CALL CloseHandle(childStdoutWrite)

    IF started = 0 THEN
        CALL CloseHandle(childStdinWrite)
        CALL CloseHandle(childStdoutRead)
        h.processHandle = 0
        NewWinUIHost = h
        EXIT FUNCTION
    END IF

    CALL CloseHandle(pi.hThread)
    h.processHandle = pi.hProcess
    h.hStdInWrite = childStdinWrite
    h.hStdOutRead = childStdoutRead
    NewWinUIHost = h
END FUNCTION

''' Reads the next unsolicited line from the host's stdout, e.g. a
''' `CLICKED <n>` button-click report - not called by anything in this
''' package yet (see README.md's "out of scope for now"), kept as the
''' raw building block a future round can poll or watch. Blocking; ""
''' if the host process has exited.
FUNCTION WinUIHostReadEvent(h AS WinUIHost) AS ZSTRING
    winuiScratch = WinUIReadLine(h)
    WinUIHostReadEvent = winuiScratch
END FUNCTION

''' Updates the host window's TextBlock. Returns the host's own raw
''' acknowledgement line (e.g. "OK SETTEXT hi") - a real, verifiable
''' proof the command reached and mutated the live WinUI3 object, since
''' there's no way to visually confirm a native window updated from
''' outside the process; check for an "OK " prefix rather than assuming
''' success.
FUNCTION WinUIHostSetText(h AS WinUIHost, text AS ZSTRING) AS ZSTRING
    DIM textStr AS STRING
    textStr = text
    CALL WinUIHostSendCommand(h, "SETTEXT " & textStr)
    winuiScratch = WinUIReadLine(h)
    WinUIHostSetText = winuiScratch
END FUNCTION

''' Updates the host window's title. Same "OK "-prefixed acknowledgement
''' contract as WinUIHostSetText.
FUNCTION WinUIHostSetTitle(h AS WinUIHost, title AS ZSTRING) AS ZSTRING
    DIM titleStr AS STRING
    titleStr = title
    CALL WinUIHostSendCommand(h, "SETTITLE " & titleStr)
    winuiScratch = WinUIReadLine(h)
    WinUIHostSetTitle = winuiScratch
END FUNCTION

''' Asks the host to close its window and exit, blocks for its final
''' acknowledgement, then releases this side's own pipe/process handles.
''' Safe to call even if the host already exited on its own (a closed
''' pipe just makes the final read return "" immediately).
SUB WinUIHostClose(h AS WinUIHost)
    CALL WinUIHostSendCommand(h, "QUIT")
    DIM ack AS STRING
    ack = WinUIReadLine(h)
    CALL CloseHandle(h.hStdInWrite)
    CALL CloseHandle(h.hStdOutRead)
    CALL CloseHandle(h.processHandle)
END SUB
