#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif
#include <string>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;

namespace winrt::smoke::implementation
{
    // Defined in main.cpp - the title/message this process was launched
    // with, and a click notifier that echoes the running count to stdout.
    std::wstring InitialTitle();
    std::wstring InitialMessage();
    void NotifyClick(int clickCount);

    static int s_clickCount = 0;

    MainWindow::MainWindow()
    {
        InitializeComponent();
        Title(InitialTitle());
        myText().Text(InitialMessage());

        // Started last, once every member this thread's own posted
        // commands could touch (myText/myButton/Title, all wired up by
        // InitializeComponent above) is already fully live.
        m_readerThread = std::thread(&MainWindow::ReaderThreadMain, this);
    }

    MainWindow::~MainWindow()
    {
        if (m_readerThread.joinable()) {
            // The reader thread only ever exits on its own (EOF on stdin,
            // or after handing off a QUIT) - never signaled to stop from
            // here, so this simply waits for whichever of those already
            // happened (real app shutdown always goes through one or the
            // other first).
            m_readerThread.join();
        }
    }

    void MainWindow::myButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        NotifyClick(++s_clickCount);
        myButton().Content(box_value(L"Clicked " + winrt::to_hstring(s_clickCount) + L"x"));
    }

    // eb-winui: one command per line from stdin - "SETTEXT <text>",
    // "SETTITLE <text>", or "QUIT". Blocks on fgetws (matches
    // NotifyClick's own plain-C-stdio convention, rather than mixing in
    // C++ iostreams) until a line is available or stdin closes (EOF,
    // e.g. the launching eBasic process exited or closed its write
    // handle) - treated as an implicit QUIT, so this host never becomes
    // an orphaned zombie window if its parent goes away without sending
    // one explicitly.
    void MainWindow::ReaderThreadMain()
    {
        wchar_t buf[4096];
        for (;;) {
            if (!fgetws(buf, static_cast<int>(std::size(buf)), stdin)) {
                HandleCommandOnUiThread(L"QUIT");
                return;
            }
            std::wstring line(buf);
            while (!line.empty() && (line.back() == L'\n' || line.back() == L'\r')) {
                line.pop_back();
            }
            bool isQuit = line == L"QUIT";
            HandleCommandOnUiThread(line);
            if (isQuit) return;
        }
    }

    // Runs on the UI thread (via DispatcherQueue::TryEnqueue - real
    // WinUI3/XAML objects may only be touched from there, never directly
    // from ReaderThreadMain's own background thread). Writes "OK <line>"
    // to stdout only once the mutation has actually been applied - the
    // real, verifiable acknowledgement a launching eBasic program can
    // wait for, since there's no way to visually confirm a native window
    // updated from outside the process.
    // Splits "<first token> <rest of line>" - `rest` is "" (not, say,
    // missing) when there's no space at all, matching this file's own
    // established one-space-delimited, ZSTRING-style parsing convention.
    static void SplitFirstWord(std::wstring const& s, std::wstring& first, std::wstring& rest)
    {
        size_t sp = s.find(L' ');
        first = sp == std::wstring::npos ? s : s.substr(0, sp);
        rest = sp == std::wstring::npos ? L"" : s.substr(sp + 1);
    }

    // "ROOT" (the reserved sentinel every command's own <parentId> can
    // pass for the common case) resolves directly to rootPanel(); any
    // other id is looked up in m_widgets and must itself be a Panel
    // (StackPanel/Grid both satisfy this) - a plain Button/TextBlock id
    // passed as a parentId is a real, reported error, not a silent
    // no-op. Returns nullptr on any failure to resolve.
    Controls::Panel MainWindow::ResolveParentPanel(std::wstring const& parentId)
    {
        if (parentId == L"ROOT") {
            return rootPanel();
        }
        auto it = m_widgets.find(parentId);
        if (it == m_widgets.end()) {
            return nullptr;
        }
        return it->second.element.try_as<Controls::Panel>();
    }

    void MainWindow::HandleCommandOnUiThread(std::wstring line)
    {
        auto self = this;
        DispatcherQueue().TryEnqueue([self, line]() {
            std::wstring cmd, arg;
            SplitFirstWord(line, cmd, arg);

            if (cmd == L"SETTEXT") {
                self->myText().Text(arg);
            } else if (cmd == L"SETTITLE") {
                self->Title(arg);
            } else if (cmd == L"SET") {
                // "SET <id> <text>" - updates a PREVIOUSLY-ADDed widget by
                // id (never the original myText/myButton - those stay
                // SETTEXT/SETTITLE's own job, see README's own note on
                // why the two aren't overloaded together). try_as is the
                // real, idiomatic WinRT cast (a QueryInterface-shaped
                // check, empty on mismatch rather than throwing) - needed
                // because Content/Text live on the concrete Button/
                // TextBlock types, not on the common UIElement this file
                // stores every widget as.
                std::wstring id, text;
                SplitFirstWord(arg, id, text);
                auto it = self->m_widgets.find(id);
                if (it == self->m_widgets.end()) {
                    wprintf(L"ERR unknown id: %s\n", line.c_str());
                    fflush(stdout);
                    return;
                }
                if (auto btn = it->second.element.try_as<Controls::Button>()) {
                    btn.Content(box_value(text));
                } else if (auto tb = it->second.element.try_as<Controls::TextBlock>()) {
                    tb.Text(text);
                } else {
                    wprintf(L"ERR cannot SET this widget type: %s\n", line.c_str());
                    fflush(stdout);
                    return;
                }
            } else if (cmd == L"REMOVE") {
                // "REMOVE <id>" - IVector<UIElement> (Panel::Children's
                // own real type) has no direct Remove(item) - IndexOf
                // (using the stored UIElement to find the real, current
                // index) then RemoveAt is the real, confirmed pattern.
                std::wstring const& id = arg;
                auto it = self->m_widgets.find(id);
                if (it == self->m_widgets.end()) {
                    wprintf(L"ERR unknown id: %s\n", line.c_str());
                    fflush(stdout);
                    return;
                }
                uint32_t index;
                if (it->second.parent && it->second.parent.Children().IndexOf(it->second.element, index)) {
                    it->second.parent.Children().RemoveAt(index);
                }
                self->m_widgets.erase(it);
            } else if (cmd == L"ADD") {
                // "ADD BUTTON <id> <parentId> <text>" /
                // "ADD TEXTBLOCK <id> <parentId> <text>" /
                // "ADD STACKPANEL <id> <parentId> <orientation>" -
                // <id>/<parentId> are one whitespace-free token each
                // (matches every other command's own "no escaping"
                // limitation), the trailing token runs to the end of the
                // line. <parentId> "ROOT" means the original top-level
                // rootPanel - see ResolveParentPanel above.
                std::wstring widgetType, rest1, id, rest2, parentId, text;
                SplitFirstWord(arg, widgetType, rest1);
                SplitFirstWord(rest1, id, rest2);
                SplitFirstWord(rest2, parentId, text);

                Controls::Panel parentPanel = self->ResolveParentPanel(parentId);
                if (!parentPanel) {
                    wprintf(L"ERR unknown parent id: %s\n", line.c_str());
                    fflush(stdout);
                    return;
                }

                // Every widget kind is constructed purely in code (no
                // XAML needed - real, documented C++/WinRT: a Panel's own
                // Children is a live IVector<UIElement>, Append() adds it
                // to the visual tree immediately) and registered in
                // m_widgets under its own parent/element pair, so a later
                // SET/REMOVE/ADD-as-parent can find it again.
                if (widgetType == L"BUTTON") {
                    Controls::Button btn;
                    btn.Content(box_value(text));
                    btn.Click([id](IInspectable const&, RoutedEventArgs const&) {
                        wprintf(L"CLICKED %s\n", id.c_str());
                        fflush(stdout);
                    });
                    parentPanel.Children().Append(btn);
                    self->m_widgets[id] = WidgetEntry{ parentPanel, btn };
                } else if (widgetType == L"TEXTBLOCK") {
                    Controls::TextBlock tb;
                    tb.Text(text);
                    parentPanel.Children().Append(tb);
                    self->m_widgets[id] = WidgetEntry{ parentPanel, tb };
                } else if (widgetType == L"STACKPANEL") {
                    // `text` holds the orientation token here, not
                    // display text - real Controls::StackPanel/Grid are
                    // both real, default-constructible, nestable exactly
                    // like Button/TextBlock (WinUI3 has an actual native
                    // layout engine, unlike Win32).
                    Controls::StackPanel sp;
                    sp.Orientation(text == L"HORIZONTAL" ? Controls::Orientation::Horizontal : Controls::Orientation::Vertical);
                    parentPanel.Children().Append(sp);
                    self->m_widgets[id] = WidgetEntry{ parentPanel, sp };
                } else {
                    wprintf(L"ERR unknown widget type: %s\n", line.c_str());
                    fflush(stdout);
                    return;
                }
            } else if (cmd == L"QUIT") {
                wprintf(L"OK %s\n", line.c_str());
                fflush(stdout);
                self->Close();
                return;
            } else {
                wprintf(L"ERR unknown command: %s\n", line.c_str());
                fflush(stdout);
                return;
            }
            wprintf(L"OK %s\n", line.c_str());
            fflush(stdout);
        });
    }
}
