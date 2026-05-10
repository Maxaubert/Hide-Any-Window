using System;
using System.Linq;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HideAnyWindowManager;

public sealed partial class MainWindow : Window
{
    public MainViewModel ViewModel { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        RulesList.ItemsSource = ViewModel.Rules;
        _ = LoadAsync();
    }

    private async System.Threading.Tasks.Task LoadAsync()
    {
        var cfg = await App.ConfigStore.LoadAsync();
        ViewModel.LoadFrom(cfg);
    }

    private void RulesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ViewModel.SelectedRule = RulesList.SelectedItem as RuleViewModel;
        RemoveButton.IsEnabled = ViewModel.CanRemove;
    }

    private void RuleToggle_Toggled(object sender, RoutedEventArgs e)
    {
        // The two-way binding has already updated the VM; persist.
        SaveDebounced();
    }

    private void RemoveButton_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedRule is null) return;
        ViewModel.Rules.Remove(ViewModel.SelectedRule);
        ViewModel.SelectedRule = null;
        RemoveButton.IsEnabled = false;
        SaveDebounced();
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
            ViewModel.Rules.Add(new RuleViewModel(new Rule
            {
                Id = Rule.IdFromExe(proc.Exe),
                Exe = proc.Exe,
                Name = proc.Name,
                Enabled = true,
            }));
            SaveDebounced();
        }
    }

    private void ServiceButton_Click(object sender, RoutedEventArgs e)
    {
        // Implemented in Task 9
    }

    private void SaveDebounced()
    {
        var cfg = ViewModel.ToConfig(ViewModel.IsServiceRunning ? "running" : "stopped");
        App.ConfigStore.ScheduleSave(cfg);
    }
}
