' Raw FFI layer: just enough of Kernel32's process/pipe API to launch a
' child process with its stdin/stdout redirected through anonymous
' pipes and talk to it - CreateProcessA (not the one-shot, no-handles
' ShellExecuteA the original winui3_shim example used), CreatePipe,
' ReadFile/WriteFile, SetHandleInformation (un-inherit the parent's own
' kept pipe ends - CreatePipe makes both ends of a pipe inheritable
' together, so without this the child would also inherit our own end
' and the pipe would never see EOF), CloseHandle, and PeekNamedPipe
' (kept for a future non-blocking WinUIHostReadEvent; not used by the
' synchronous version this round ships).
'
' Struct layouts mirror win32_types.bas's own field-for-field
' discipline: each eBasic field's declared type is the same size as the
' real Win32 struct member it stands in for, so the compiler's own
' natural aggregate padding reproduces the real layout exactly - see
' Win32StartupInfoA's own comment for the one place that matters here.

TYPE Win32SecurityAttributes
    nLength AS UINTEGER
    lpSecurityDescriptor AS ANY PTR
    bInheritHandle AS INTEGER
END TYPE

' wShowWindow/cbReserved2 are the real struct's own two WORDs, declared
' USHORT (not UINTEGER) specifically so the compiler's own natural
' pointer alignment inserts the same 4 bytes of padding before
' lpReserved2 that the real STARTUPINFOA gets - two UINTEGERs here
' would happen to total the same 8 bytes today, but only by
' coincidence; USHORT reproduces the real field widths, not just the
' final size.
TYPE Win32StartupInfoA
    cb AS UINTEGER
    lpReserved AS ANY PTR
    lpDesktop AS ANY PTR
    lpTitle AS ANY PTR
    dwX AS UINTEGER
    dwY AS UINTEGER
    dwXSize AS UINTEGER
    dwYSize AS UINTEGER
    dwXCountChars AS UINTEGER
    dwYCountChars AS UINTEGER
    dwFillAttribute AS UINTEGER
    dwFlags AS UINTEGER
    wShowWindow AS USHORT
    cbReserved2 AS USHORT
    lpReserved2 AS ANY PTR
    hStdInput AS ANY PTR
    hStdOutput AS ANY PTR
    hStdError AS ANY PTR
END TYPE

TYPE Win32ProcessInformation
    hProcess AS ANY PTR
    hThread AS ANY PTR
    dwProcessId AS UINTEGER
    dwThreadId AS UINTEGER
END TYPE

Extern "C" Lib "kernel32"
    Declare Function CreatePipe Stdcall (ByVal readHandle AS ANY PTR, ByVal writeHandle AS ANY PTR, ByVal attrs AS Win32SecurityAttributes PTR, ByVal size AS UINTEGER) AS INTEGER

    ' The real signature's `bInheritHandle` OUT-parameter effect on
    ' `hObject` matters more than the return value here - always called
    ' with `dwMask = HANDLE_FLAG_INHERIT` (1), `dwFlags = 0`, to strip
    ' inheritance from whichever pipe end this process is keeping for
    ' itself right after CreatePipe hands back an inheritable pair.
    Declare Function SetHandleInformation Stdcall (ByVal handle AS ANY PTR, ByVal mask AS UINTEGER, ByVal flags AS UINTEGER) AS INTEGER

    ' lpApplicationName/lpCurrentDirectory are always passed 0 (NULL) by
    ' this package's own NewWinUIHost - declared ANY PTR, not ZSTRING,
    ' for exactly the reason GetModuleHandleA's own moduleName parameter
    ' is (see kernel32.bas in eb-win32): only a bare `0` literal needs to
    ' pass through cleanly, no real string is ever supplied here.
    Declare Function CreateProcessA Stdcall (ByVal applicationName AS ANY PTR, ByVal commandLine AS ZSTRING, ByVal processAttrs AS ANY PTR, ByVal threadAttrs AS ANY PTR, ByVal inheritHandles AS INTEGER, ByVal creationFlags AS UINTEGER, ByVal environment AS ANY PTR, ByVal currentDirectory AS ANY PTR, ByVal startupInfo AS Win32StartupInfoA PTR, ByVal processInformation AS Win32ProcessInformation PTR) AS INTEGER

    ' Named Win32ReadFile/Win32WriteFile, not the real API's own bare
    ' `ReadFile`/`WriteFile` (every other declaration in this file keeps
    ' the real Win32 name unprefixed) - eBasic's own File Library
    ' pre-declares exactly those two names for whole-file read/write
    ' (see file-library.md), so the real, unprefixed names are already
    ' taken in every program that includes this package.
    '
    ' `buffer` is declared ANY PTR (the real LPVOID) for Win32ReadFile -
    ' the caller always supplies the address of a stack-local UBYTE
    ' array, never a STRING - and ZSTRING for Win32WriteFile, since
    ' every write this package makes is already a real STRING command
    ' line, which converts to ZSTRING automatically at the call site
    ' (see extern-interop.md's "ZSTRING at the interop boundary") - no
    ' manual buffer needed on the write side at all.
    Declare Function Win32ReadFile Stdcall Alias "ReadFile" (ByVal handle AS ANY PTR, ByVal buffer AS ANY PTR, ByVal bytesToRead AS UINTEGER, ByVal bytesRead AS ANY PTR, ByVal overlapped AS ANY PTR) AS INTEGER
    Declare Function Win32WriteFile Stdcall Alias "WriteFile" (ByVal handle AS ANY PTR, ByVal buffer AS ZSTRING, ByVal bytesToWrite AS UINTEGER, ByVal bytesWritten AS ANY PTR, ByVal overlapped AS ANY PTR) AS INTEGER

    ' Kept for a future non-blocking WinUIHostReadEvent (PeekNamedPipe
    ' can report "0 bytes available" without blocking, unlike ReadFile) -
    ' not called by anything in this package yet.
    Declare Function PeekNamedPipe Stdcall (ByVal handle AS ANY PTR, ByVal buffer AS ANY PTR, ByVal bufferSize AS UINTEGER, ByVal bytesRead AS ANY PTR, ByVal totalBytesAvail AS ANY PTR, ByVal bytesLeftThisMessage AS ANY PTR) AS INTEGER

    Declare Function CloseHandle Stdcall (ByVal handle AS ANY PTR) AS INTEGER
End Extern
