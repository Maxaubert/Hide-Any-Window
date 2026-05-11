using Microsoft.UI.Xaml;
using HideAnyWindowManager.Services;

namespace HideAnyWindowManager;

public partial class App : Application
{
    public static ConfigStore ConfigStore { get; } = new();
    public static ServiceController ServiceController { get; } = new();
    public static ProcessEnumerator ProcessEnumerator { get; } = new();
    public static AutostartManager AutostartManager { get; } = new();

    private Window? _mainWindow;

    public App() { InitializeComponent(); }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _mainWindow = new MainWindow();
        _mainWindow.Activate();
    }
}
