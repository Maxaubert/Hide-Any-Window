using System;
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
        var cli = Environment.GetCommandLineArgs();
        for (int i = 1; i < cli.Length; i++)
        {
            if (string.Equals(cli[i], AutostartManager.StartServiceArg, StringComparison.OrdinalIgnoreCase))
            {
                // Logon-trigger path: ShellExecute the uiAccess service and exit without UI.
                ServiceController.TryStartService();
                Environment.Exit(0);
                return;
            }
        }

        _mainWindow = new MainWindow();
        _mainWindow.Activate();

        // If autostart was enabled in an older build (task points at the uiAccess service
        // directly, which Task Scheduler can't launch — fails with ERROR_ELEVATION_REQUIRED),
        // re-register so the task points at this manager + --start-service.
        try { if (AutostartManager.IsEnabled()) AutostartManager.TryEnable(); }
        catch { /* non-fatal */ }
    }
}
