# eb-winui: driving a live WinUI3 window from eBasic

Real, bidirectional WinUI3 (Windows App SDK / Fluent Design) bindings for
eBasic - the MSVC/clang-cl counterpart to
[eb-win32](https://github.com/yann64/eb-win32)'s g++/clang++ raw Win32
bindings, filling the "WinUI bindings" half of that original split.

Two pieces:

- **`host/`** - a real, hand-written C++/WinRT WinUI3 application
  (`eb_winui3_host.vcxproj`), built with plain command-line `msbuild`. It
  shows a `TextBlock` and a `Button` in a single window, and reads simple
  text commands from its own **stdin** - `SETTEXT <text>`, `SETTITLE
  <text>`, `QUIT` - writing `OK <command>` back to **stdout** once each one
  is actually applied (or `CLICKED <n>` on a button click).
- **`src/`** - the eBasic side: `raw/win32_process.bas` (Kernel32
  `CreateProcessA`/`CreatePipe`/`ReadFile`/`WriteFile` bindings) plus
  `winui.bas`, an idiomatic `WinUIHost` type that launches `host/`'s own
  `.exe` with its stdin/stdout redirected through anonymous pipes and talks
  to it over that same protocol - `NewWinUIHost`, `WinUIHostSetText`,
  `WinUIHostSetTitle`, `WinUIHostReadEvent`, `WinUIHostClose`.

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

Opens a WinUI3 window, then updates its text and title from eBasic,
printing the host's own real acknowledgement for each - proof the command
channel really reached and mutated the live WinUI3 objects, not just that
the process launched.

## The protocol

One command per line, written to the host's stdin:

| Command | Effect | Acknowledgement |
|---|---|---|
| `SETTEXT <text>` | Sets the `TextBlock`'s text | `OK SETTEXT <text>` |
| `SETTITLE <text>` | Sets the window's title | `OK SETTITLE <text>` |
| `QUIT` | Closes the window, ends the process | `OK QUIT` |

An unrecognized command gets `ERR unknown command: <line>` instead. A
button click is reported unprompted, at any time, as `CLICKED <n>` (`n` the
running click count) - not yet consumed by anything in `src/winui.bas`
(`WinUIHostReadEvent` is the raw building block a future round can use to
watch for it).

Every line, in both directions, is plain ASCII, terminated by a single
`Chr(10)` (`\n`) - no `\r`. Accepted limitation: `SETTEXT`/`SETTITLE`'s own
`<text>` runs to the end of the line, so it can't itself contain a newline.

## Deliberately out of scope (for now)

- **Dynamic, multi-widget construction** - `host/`'s window is a fixed
  layout (one `TextBlock`, one `Button`); there's no `WinUIAddButton`-style
  API yet.
- **Re-attempting in-process consumption** - see "Why a separate process"
  above; not revisited here.
- **A `eb-gui-winui` adapter** implementing the shared
  [eb-gui](https://github.com/yann64/eb-gui) contract - needs dynamic
  widgets first.
- **Non-blocking event polling** - `WinUIHostReadEvent` is a blocking read;
  `PeekNamedPipe` is bound in `raw/win32_process.bas` but not used yet.
