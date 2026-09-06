# eb-winui: driving a live WinUI3 window from eBasic

Real, bidirectional WinUI3 (Windows App SDK / Fluent Design) bindings for
eBasic - the MSVC/clang-cl counterpart to
[eb-win32](https://github.com/yann64/eb-win32)'s g++/clang++ raw Win32
bindings, filling the "WinUI bindings" half of that original split.

Two pieces:

- **`host/`** - a real, hand-written C++/WinRT WinUI3 application
  (`eb_winui3_host.vcxproj`), built with plain command-line `msbuild`. It
  shows a `TextBlock` and a `Button` in a fixed layout, plus any further
  widgets/containers added at runtime, and reads simple text commands
  from its own **stdin** - `SETTEXT`/`SETTITLE`/`ADD`/`SET`/`REMOVE`/
  `QUIT` (see "The protocol" below) - writing `OK <command>` back to
  **stdout** once each one is actually applied (or `CLICKED <id>` on a
  button click, `<id>` either `myButton`'s own running click count or a
  dynamically-added button's own `<id>`).
- **`src/`** - the eBasic side: `raw/win32_process.bas` (Kernel32
  `CreateProcessA`/`CreatePipe`/`ReadFile`/`WriteFile` bindings) plus
  `winui.bas`, an idiomatic `WinUIHost` type that launches `host/`'s own
  `.exe` with its stdin/stdout redirected through anonymous pipes and talks
  to it over that same protocol - `NewWinUIHost`, `WinUIHostSetText`,
  `WinUIHostSetTitle`, `WinUIHostAddButton`, `WinUIHostAddTextBlock`,
  `WinUIHostAddStackPanel`, `WinUIHostSet`, `WinUIHostRemove`,
  `WinUIHostReadEvent`, `WinUIHostClose`.

## Status

`0.3.0`. Round 1 shipped the fixed one-`TextBlock`-one-`Button` layout and
the `SETTEXT`/`SETTITLE`/`QUIT` protocol. Round 2 added dynamic,
multi-widget construction (`ADD BUTTON`/`ADD TEXTBLOCK`, real
`Microsoft::UI::Xaml::Controls` objects constructed purely in code, no
XAML). Round 3 closed the two gaps Round 2 itself named: `SET <id>
<text>`/`REMOVE <id>` update/remove a previously-`ADD`ed widget by id
(never the original static `TextBlock`/title - those stay `SETTEXT`/
`SETTITLE`'s own job, kept deliberately un-overloaded, see "The
protocol" below), and `ADD STACKPANEL <id> <parentId> <orientation>`
gives real, native nested containers - `Controls::StackPanel`/`Grid` are
both real, default-constructible, nestable exactly like `Button`/
`TextBlock` already were, so WinUI3's layout story is structurally
simpler here than Win32's own from-scratch one (see `eb-win32`'s
`Win32Box`). Every `ADD` now takes an explicit `<parentId>` (`"ROOT"`
for the original top-level body) - a real, breaking protocol change from
Round 2, acceptable pre-1.0.

**A real, load-bearing limitation found while updating `examples/
hello_winui`**: `WinUIHostAddButton`/`AddTextBlock`/`AddStackPanel`'s own
trailing `parentId AS ZSTRING = "ROOT"` default parameter does not carry
across a `--lib` package boundary - `ebc` requires every argument
explicitly at a cross-package call site regardless of a declared
default (confirmed: omitting it fails with "missing required argument"
against the very same function that compiles fine default-and-all
*inside* this package's own `winui.bas`). The default stays in the
source (harmless, and correct for any future same-package caller) but
buys no real convenience for `hello_winui` or any other consumer today -
always pass `parentId` explicitly cross-package until/unless this gets
fixed upstream in `ebc` itself.

Verified live twice, at two different layers: directly against the real
host process (`.NET`-driven pipes, bypassing the eBasic side, to isolate
the *host*'s own new behavior) - `SET`/`REMOVE`/nested `ADD STACKPANEL`
all get real `OK ...` acknowledgements, and a real screenshot confirms a
renamed button, two buttons genuinely laid out side-by-side inside a
real horizontal `StackPanel`, and a removed widget's real absence; and
end-to-end through the compiled `hello_winui.exe` itself, which this
round's own run was **not** blocked by the transient Windows
Application Control policy noted in Round 2's own status (that block
cleared on its own, exactly as the general pattern this whole project
has seen elsewhere predicts) - full real output captured, including the
one deliberately-triggered error case (`SET` on an unknown id).

No new missing-include bug this round, unlike Rounds 1 and 2 - `pch.h`
got its `<unordered_map>` (for the new id -> widget lookup table) added
proactively up front, applying the exact lesson those two earlier
rounds established, and the host built clean on the first real attempt.

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
a text block, updates and removes them, adds a nested horizontal
`StackPanel` with a button inside it, exercises one real error case, and
closes it - printing the host's own real acknowledgement for each -
proof the command channel really reached and mutated the live WinUI3
objects, not just that the process launched.

## The protocol

One command per line, written to the host's stdin (`<parentId>` is
`"ROOT"` for the original top-level window body, or a previously-`ADD`ed
`STACKPANEL`/`GRID`'s own id):

| Command | Effect | Acknowledgement |
|---|---|---|
| `SETTEXT <text>` | Sets the original `TextBlock`'s text | `OK SETTEXT <text>` |
| `SETTITLE <text>` | Sets the window's title | `OK SETTITLE <text>` |
| `ADD BUTTON <id> <parentId> <text>` | Creates a new Button inside `<parentId>` | `OK ADD BUTTON <id> <parentId> <text>` |
| `ADD TEXTBLOCK <id> <parentId> <text>` | Creates a new, static TextBlock, same placement rules | `OK ADD TEXTBLOCK <id> <parentId> <text>` |
| `ADD STACKPANEL <id> <parentId> <orientation>` | Creates a nested container (`HORIZONTAL`/`VERTICAL`) | `OK ADD STACKPANEL <id> <parentId> <orientation>` |
| `SET <id> <text>` | Updates a previously-`ADD`ed widget's own text (never the original `TextBlock`/title) | `OK SET <id> <text>` |
| `REMOVE <id>` | Removes a previously-`ADD`ed widget from its own parent | `OK REMOVE <id>` |
| `QUIT` | Closes the window, ends the process | `OK QUIT` |

`SETTEXT`/`SETTITLE` are deliberately never overloaded to also accept an
id - `SET`/`REMOVE` only ever target something `ADD` created. An
unrecognized command gets `ERR unknown command: <line>`; `ADD` with an
unrecognized widget type or unresolvable `<parentId>` gets `ERR unknown
widget type: <line>`/`ERR unknown parent id: <line>`; `SET`/`REMOVE` on
an id that doesn't exist (or a `SET` naming a widget with no `Content`/
`Text` property, e.g. a `STACKPANEL`) gets `ERR unknown id: <line>`/`ERR
cannot SET this widget type: <line>`. A button click - the original
`myButton`, or any dynamically-added one - is reported unprompted, at
any time, as `CLICKED <id>` (the original button's own running click
count as a string, or a dynamic button's own `<id>`) - not yet consumed
by anything in `src/winui.bas` (`WinUIHostReadEvent` is the raw building
block a future round can use to watch for it).

Every line, in both directions, is plain ASCII, terminated by a single
`Chr(10)` (`\n`) - no `\r`. Accepted limitation: every command's own final
token runs to the end of the line (so it can't itself contain a
newline), and every `<id>`/`<parentId>` is one whitespace-free token,
same rule. `REMOVE`-ing a `STACKPANEL`/`GRID` container does *not*
cascade to its own children - they stay live WinRT objects, just no
longer reachable by any `id` (a real, accepted limitation: the whole
process exits with the window regardless, so nothing is actually leaked
in the sense that matters).

## Deliberately out of scope (for now)

- **Re-attempting in-process consumption** - see "Why a separate process"
  above; not revisited here.
- **A `eb-gui-winui` adapter** implementing the shared
  [eb-gui](https://github.com/yann64/eb-gui) contract - now that dynamic
  widgets and containers exist, a real, later round, not this one.
- **Non-blocking event polling** - `WinUIHostReadEvent` is a blocking read;
  `PeekNamedPipe` is bound in `raw/win32_process.bas` but not used yet.
- **`ADD GRID`** - `StackPanel` is the only container this round; `Grid`
  is real, confirmed, equally constructible WinRT API, just not wired
  into the protocol yet.
- **Cascading `REMOVE`** for a container's own children, and reclaiming
  a removed widget's own id for reuse.
- **Widget kinds beyond `BUTTON`/`TEXTBLOCK`/`STACKPANEL`** - matches
  this round's own "prove the mechanism on the smallest useful surface"
  scope.
