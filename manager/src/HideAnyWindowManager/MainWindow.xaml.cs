using System;
using System.Linq;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using HideAnyWindowManager.Util;
using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace HideAnyWindowManager;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    private Microsoft.UI.Xaml.DispatcherTimer? _statusTimer;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        RulesList.ItemsSource = ViewModel.Rules;
        _ = LoadAsync();
        StartStatusWatch();
    }

    private void StartStatusWatch()
    {
        _statusTimer = new Microsoft.UI.Xaml.DispatcherTimer
        {
            Interval = System.TimeSpan.FromSeconds(1),
        };
        _statusTimer.Tick += (_, __) => RefreshStatus();
        _statusTimer.Start();
        RefreshStatus();
    }

    private async void RefreshStatus()
    {
        bool mutex = App.ServiceController.IsServiceRunning();
        var cfg = await App.ConfigStore.LoadAsync();
        bool effective = mutex && cfg.ServiceState == "running";

        // Keep VM in sync with disk so SaveDebounced preserves external changes.
        ViewModel.ServiceState = cfg.ServiceState;
        ViewModel.IsServiceRunning = effective;

        StatusDot.Fill = new SolidColorBrush(effective
            ? Color.FromArgb(0xFF, 0x2E, 0x9C, 0x4F)
            : Color.FromArgb(0xFF, 0x88, 0x88, 0x88));
        StatusLabel.Text = ViewModel.StatusText;
        ServiceButton.Content = ViewModel.ServiceButtonText;
    }

    private async System.Threading.Tasks.Task LoadAsync()
    {
        var cfg = await App.ConfigStore.LoadAsync();
        ViewModel.LoadFrom(cfg);
        foreach (var rvm in ViewModel.Rules)
            _ = LoadIconForRuleAsync(rvm);
    }

    private async System.Threading.Tasks.Task LoadIconForRuleAsync(RuleViewModel rvm)
    {
        if (string.IsNullOrEmpty(rvm.Path)) return;
        rvm.Icon = await IconHelper.LoadIconAsync(rvm.Path);
    }

    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ViewModel.SelectedRule = RulesList.SelectedItem as RuleViewModel;
    }

    private void RuleToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleSwitch ts && ts.DataContext is RuleViewModel rvm)
        {
            // WinUI 3's TwoWay binding may not have propagated the user's
            // change to the source by the time Toggled fires, leaving rvm.Enabled
            // one step behind ts.IsOn. Force the sync explicitly so SaveDebounced
            // writes what the user actually sees.
            var oldEnabled = rvm.Enabled;
            rvm.Enabled = ts.IsOn;
            ManagerLog.Write($"toggle ruleId={rvm.Id} ts.IsOn={ts.IsOn} oldEnabled={oldEnabled} -> Enabled={rvm.Enabled}");
        }
        SaveDebounced();
    }

    private void DeleteRowButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.DataContext is RuleViewModel rvm)
        {
            ViewModel.Rules.Remove(rvm);
            ManagerLog.Write($"removed rule ruleId={rvm.Id}");
            SaveDebounced();
        }
    }

    private async void AddButton_Click(object sender, RoutedEventArgs e)
    {
        var existingExes = ViewModel.Rules.Select(r => r.Exe).ToList();
        var dialog = new AddPickerDialog(App.ProcessEnumerator, existingExes)
        {
            XamlRoot = ((FrameworkElement)Content).XamlRoot,
        };
        var result = await dialog.ShowAsync();
        if (dialog.WasConfirmed(result) && dialog.SelectedProcess is { } proc)
        {
            var newRvm = new RuleViewModel(new Rule
            {
                Id = Rule.IdFromExe(proc.Exe),
                Exe = proc.Exe,
                Path = proc.FullPath,
                Name = proc.Name,
                Enabled = true,
            });
            ViewModel.Rules.Add(newRvm);
            _ = LoadIconForRuleAsync(newRvm);
            SaveDebounced();
        }
    }

    private async void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        var cfg = await App.ConfigStore.LoadAsync();
        bool mutex = App.ServiceController.IsServiceRunning();

        if (!mutex)
        {
            // Process not running -> ensure state is "running" then launch.
            cfg.ServiceState = "running";
            ViewModel.ServiceState = "running";
            await App.ConfigStore.SaveImmediateAsync(cfg);
            ManagerLog.Write("ServiceButton: launching (mutex absent, set state=running)");
            if (!App.ServiceController.TryStartService())
            {
                var script = HideAnyWindowManager.Services.ServiceController.DefaultScriptPath();
                var ahkUia = HideAnyWindowManager.Services.ServiceController.DefaultAhkUiaPath();
                var dlg = new ContentDialog
                {
                    Title = "Couldn't start service",
                    Content = $"One of these wasn't found:\n\n  AHK UIA exe:  {ahkUia}\n  Service script:  {script}\n\nVerify both paths exist.",
                    CloseButtonText = "OK",
                    XamlRoot = ((FrameworkElement)Content).XamlRoot,
                };
                await dlg.ShowAsync();
            }
        }
        else if (cfg.ServiceState == "running")
        {
            // Process running, currently active -> pause.
            cfg.ServiceState = "stopped";
            ViewModel.ServiceState = "stopped";
            await App.ConfigStore.SaveImmediateAsync(cfg);
            ManagerLog.Write("ServiceButton: pausing (mutex held, state was running -> stopped)");
        }
        else
        {
            // Process running, paused -> resume.
            cfg.ServiceState = "running";
            ViewModel.ServiceState = "running";
            await App.ConfigStore.SaveImmediateAsync(cfg);
            ManagerLog.Write("ServiceButton: resuming (mutex held, state was stopped -> running)");
        }
        RefreshStatus();
    }

    private void SaveDebounced()
    {
        var cfg = ViewModel.ToConfig();
        var ruleSummary = string.Join(", ", cfg.Rules.Select(r => $"{r.Id}={(r.Enabled ? "on" : "off")}"));
        ManagerLog.Write($"SaveDebounced state={cfg.ServiceState} rules=[{ruleSummary}]");
        App.ConfigStore.ScheduleSave(cfg);
    }
}
