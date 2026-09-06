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
        // ("SETTEXT <text>"/"SETTITLE <text>"/"ADD ..."/"SET ..."/
        // "REMOVE ..."/"QUIT") in a loop on its own thread - real
        // WinUI3/XAML objects may only be touched from the UI thread, so
        // each parsed command is marshaled onto it via
        // DispatcherQueue::TryEnqueue (HandleCommandOnUiThread) rather
        // than applied directly here. Joined in the destructor.
        void ReaderThreadMain();
        void HandleCommandOnUiThread(std::wstring line);
        Microsoft::UI::Xaml::Controls::Panel ResolveParentPanel(std::wstring const& parentId);
        std::thread m_readerThread;

        // A dynamically-added widget's own parent Panel (needed for
        // REMOVE - Panel::Children() has no direct Remove(item), only
        // IndexOf + RemoveAt) and its UIElement (try_as<Button>/
        // <TextBlock>/<Panel> at SET/REMOVE/ADD-<container> time to know
        // which real property/collection applies).
        struct WidgetEntry
        {
            Microsoft::UI::Xaml::Controls::Panel parent{ nullptr };
            Microsoft::UI::Xaml::UIElement element{ nullptr };
        };
        std::unordered_map<std::wstring, WidgetEntry> m_widgets;
    };
}

namespace winrt::smoke::factory_implementation
{
    struct MainWindow : MainWindowT<MainWindow, implementation::MainWindow>
    {
    };
}
