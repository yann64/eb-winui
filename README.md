# eb-winui: driving a live WinUI3 window from eBasic

Real, bidirectional WinUI3 (Windows App SDK / Fluent Design) bindings for
eBasic - the MSVC/clang-cl counterpart to
[eb-win32](https://github.com/yann64/eb-win32)'s g++/clang++ raw Win32
bindings, filling the "WinUI bindings" half of that original split.

Two pieces:

- **`host/`** - a real, hand-written C++/WinRT WinUI3 application
  (`eb_winui3_host.vcxproj`), built with plain command-line `msbuild`. It
  shows a `TextBlock` and a `Button` in a fixed layout, plus any further
  widgets added at runtime, and reads simple text commands from its own
  **stdin** - `SETTEXT <text>`, `SETTITLE <text>`, `ADD BUTTON <id> <text>`,
  `ADD TEXTBLOCK <id> <text>`, `QUIT` - writing `OK <command>` back to
  **stdout** once each one is actually applied (or `CLICKED <id>` on a
  button click, `<id>` either `myButton`'s own running click count or a
  dynamically-added button's own `<id>`).
- **`src/`** - the eBasic side: `raw/win32_process.bas` (Kernel32
  `CreateProcessA`/`CreatePipe`/`ReadFile`/`WriteFile` bindings) plus
  `winui.bas`, an idiomatic `WinUIHost` type that launches `host/`'s own
  `.exe` with its stdin/stdout redirected through anonymous pipes and talks
  to it over that same protocol - `NewWinUIHost`, `WinUIHostSetText`,
  `WinUIHostSetTitle`, `WinUIHostAddButton`, `WinUIHostAddTextBlock`,
  `WinUIHostReadEvent`, `WinUIHostClose`.

## Status

`0.2.0`. Round 1 shipped the fixed one-`TextBlock`-one-`Button` layout and
the `SETTEXT`/`SETTITLE`/`QUIT` protocol. Round 2 added dynamic,
multi-widget construction: `ADD BUTTON`/`ADD TEXTBLOCK` create real WinUI3
controls at runtime (`Microsoft::UI::Xaml::Controls::Button`/`TextBlock`
constructed purely in code, `Panel.Children.Append`-ed to the visual tree -
no XAML involved), and any dynamically-added button reports its own
`CLICKED <id>` independently.

Verified live against the real host process (`.NET`-driven pipes,
bypassing the eBasic side, to isolate the *host*'s own new behavior from
the eBasic-side codegen): `ADD BUTTON`/`ADD TEXTBLOCK` both get real `OK
...` acknowledgements, and a real screenshot confirms the new widgets
actually render, appended below the original static ones, in the correct
order. The eBasic-side bindings (`WinUIHostAddButton`/`AddTextBlock`)
compile cleanly and reuse the exact same `WinUIHostSendCommand`/
`WinUIReadLine`/`winuiScratch` pattern already proven correct for
`WinUIHostSetText`/`SetTitle` in Round 1 - but running the freshly
rebuilt `hello_winui.exe` itself was blocked for this round by a
persistent, machine-local Windows Application Control policy requiring an
Enterprise signing level for any new/modified executable (confirmed via
`Microsoft-Windows-CodeIntegrity/Operational`, not the usual transient
Smart App Control flakiness noted elsewhere in this project - every
launch path tried, including `Start-Process` and a from-scratch
`Unblock-File`, failed identically). A real, honest carve-out, not a
silent gap: the *host*'s own new behavior is proven live; the compiled
example's own live run needs re-verification once that policy allows it.

Two real bugs found while extending `host/`, both the same class already
seen in Round 1 - a header missing from `pch.h` leaves only a partial
declaration of a "returns `auto`" C++/WinRT projection method in scope,
a real MSVC error (C3779), not a logic bug: `winrt/
Windows.Foundation.Collections.h` was needed for `IVector<UIElement>::
Append` (the mechanism `Panel.Children().Append(...)` actually calls).

## Why a separate process, not an in-process DLL

The first approach tried for WinUI3 bindings (see
`examples/winui3_shim/` in the main `ebasic` repository, the prototype this
package grew out of) was the more obviously "integrated" one: compile the
WinUI3 code as a DLL and have the eBasic-compiled `.exe` load it directly.
That was built and it loaded - but the window itself crashed on creation,
with a `STATUS_STOWED_EXCEPTION` (`0xc000027b`) raised from inside the
*system*-installed `Microsoft.UI.Xaml.dll`.

The root cause is the Windows App SDK's deployment model, not a bug in the
shim code: `WindowsAppSDKSelfContained=true` bundles the WinUI3 runtime
files next to the build output, but the `MddBootstrapInitialize` bootstrap
API that wires a process up to the Windows App Runtime still resolves the
actual framework package from the system-wide MSIX registration, regardless
of what's sitting next to the DLL. That's fine for a process that was built
from the ground up as a Windows App SDK app (like `eb_winui3_host` itself)
- it isn't set up to tolerate being loaded as a plugin into an arbitrary
foreign host process (like eBasic's plain-C++-runtime `.exe`) that never
initialized that context itself.

Rather than fight that boundary, this package crosses it as a **process**
boundary instead of a **linkage** boundary: `eb_winui3_host.exe` stays a
complete, independent, self-contained Windows App SDK application, and
eBasic launches it via `CreateProcessA` with its stdin/stdout redirected
through pipes - a real, live, two-way command/acknowledgement channel, not
just a one-shot `ShellExecuteA` launch. This sidesteps the DLL-loading
incompatibility entirely, and is arguably a more robust pattern anyway:
the WinUI3 window's process lifetime, message loop, and any future crash
are fully isolated from the eBasic host program.

## Building the host

Requires Visual Studio (with "Desktop development with C++" and the
Windows App SDK components) and an "x64 Native Tools" environment, or
`vcvarsall.bat` sourced first:

```bash
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
cd host
msbuild eb_winui3_host.vcxproj -t:restore -p:Configuration=Debug -p:Platform=x64
msbuild eb_winui3_host.vcxproj -p:Configuration=Debug -p:Platform=x64
```

This produces `host\x64\Debug\eb_winui3_host.exe`. The `restore` step pulls
the `Microsoft.WindowsAppSDK` and `Microsoft.Windows.CppWinRT` NuGet
packages the project references.

## Running `hello_winui`

```bash
cd examples\hello_winui
ebpm build
target\hello_winui.exe ..\..\host\x64\Debug\eb_winui3_host.exe
```

Opens a WinUI3 window, then updates its text and title, adds a button and
a text block, and closes it - printing the host's own real acknowledgement
for each - proof the command channel really reached and mutated the live
WinUI3 objects, not just that the process launched.

## The protocol

One command per line, written to the host's stdin:

| Command | Effect | Acknowledgement |
|---|---|---|
| `SETTEXT <text>` | Sets the original `TextBlock`'s text | `OK SETTEXT <text>` |
| `SETTITLE <text>` | Sets the window's title | `OK SETTITLE <text>` |
| `ADD BUTTON <id> <text>` | Creates a new Button, appended below every existing widget | `OK ADD BUTTON <id> <text>` |
| `ADD TEXTBLOCK <id> <text>` | Creates a new, static TextBlock, same placement | `OK ADD TEXTBLOCK <id> <text>` |
| `QUIT` | Closes the window, ends the process | `OK QUIT` |

An unrecognized command gets `ERR unknown command: <line>` instead, and an
`ADD` with an unrecognized widget type gets `ERR unknown widget type:
<line>`. A button click - the original `myButton`, or any dynamically-added
one - is reported unprompted, at any time, as `CLICKED <id>` (the original
button's own running click count as a string, or a dynamic button's own
`<id>`) - not yet consumed by anything in `src/winui.bas`
(`WinUIHostReadEvent` is the raw building block a future round can use to
watch for it).

Every line, in both directions, is plain ASCII, terminated by a single
`Chr(10)` (`\n`) - no `\r`. Accepted limitation: every command's own final
`<text>` runs to the end of the line (so it can't itself contain a
newline), and `ADD`'s own `<id>` is one whitespace-free token, same rule.

## Deliberately out of scope (for now)

- **Updating or removing a dynamically-added widget** - `ADD` is the only
  operation; there's no id -> control lookup table on the host side yet
  (nothing needed one, until an update-by-id operation exists to need it),
  and no `SETTEXT <id> <text>`-style targeting - the bare `SETTEXT` still
  only ever means the original, static `TextBlock`.
- **Re-attempting in-process consumption** - see "Why a separate process"
  above; not revisited here.
- **A `eb-gui-winui` adapter** implementing the shared
  [eb-gui](https://github.com/yann64/eb-gui) contract - now that dynamic
  widgets exist, a real, later round, not this one.
- **Non-blocking event polling** - `WinUIHostReadEvent` is a blocking read;
  `PeekNamedPipe` is bound in `raw/win32_process.bas` but not used yet.
- **Widget kinds beyond `BUTTON`/`TEXTBLOCK`** - matches this round's own
  "prove the mechanism on the smallest useful surface" scope.
