#pragma once

#include <windows.h>
#include <unknwn.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Navigation.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <microsoft.ui.xaml.window.h>

// eb-winui: the stdin command-reader thread and its wide-string command
// parsing (main.cpp/MainWindow.xaml.cpp).
#include <thread>
#include <string>
#include <cstdio>
