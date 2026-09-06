#pragma once
#include "MainWindow.g.h"

namespace winrt::smoke::implementation
{
    struct MainWindow : MainWindowT<MainWindow>
    {
        MainWindow();
        ~MainWindow();
        void myButton_Click(IInspectable const&, Microsoft::UI::Xaml::RoutedEventArgs const&);

    private:
        // eb-winui: reads one command per line from stdin
        // ("SETTEXT <text>"/"SETTITLE <text>"/"QUIT") in a loop on its own
        // thread - real WinUI3/XAML objects may only be touched from the
        // UI thread, so each parsed command is marshaled onto it via
        // DispatcherQueue::TryEnqueue (HandleCommandOnUiThread) rather
        // than applied directly here. Joined in the destructor.
        void ReaderThreadMain();
        void HandleCommandOnUiThread(std::wstring line);
        std::thread m_readerThread;
    };
}

namespace winrt::smoke::factory_implementation
{
    struct MainWindow : MainWindowT<MainWindow, implementation::MainWindow>
    {
    };
}
