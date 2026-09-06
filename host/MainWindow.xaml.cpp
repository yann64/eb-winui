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
    void MainWindow::HandleCommandOnUiThread(std::wstring line)
    {
        auto self = this;
        DispatcherQueue().TryEnqueue([self, line]() {
            size_t sp = line.find(L' ');
            std::wstring cmd = sp == std::wstring::npos ? line : line.substr(0, sp);
            std::wstring arg = sp == std::wstring::npos ? L"" : line.substr(sp + 1);

            if (cmd == L"SETTEXT") {
                self->myText().Text(arg);
            } else if (cmd == L"SETTITLE") {
                self->Title(arg);
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
