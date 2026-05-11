using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using HideAnyWindowManager.Util;
using HideAnyWindowManager.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace HideAnyWindowManager;

public sealed partial class AddPickerDialog : ContentDialog
{
    private readonly List<PickerRow> _all;
    private bool _doubleTapConfirmed;
    public WindowedProcessInfo? SelectedProcess { get; private set; }

    public AddPickerDialog(ProcessEnumerator enumerator, IReadOnlyCollection<string> alreadyMonitoredExes)
    {
        InitializeComponent();
        _all = enumerator.EnumerateWindowedProcesses(alreadyMonitoredExes)
                         .Select(i => new PickerRow(i))
                         .ToList();
        ApplyFilter("");
        _ = LoadIconsAsync();
    }

    private async Task LoadIconsAsync()
    {
        foreach (var row in _all)
        {
            row.Icon = await IconHelper.LoadIconAsync(row.Source.FullPath);
        }
    }

    private void ApplyFilter(string text)
    {
        var filtered = string.IsNullOrWhiteSpace(text)
            ? _all
            : _all.Where(p => p.Name.Contains(text, System.StringComparison.OrdinalIgnoreCase)
                          || p.Exe.Contains(text, System.StringComparison.OrdinalIgnoreCase)).ToList();
        PickList.ItemsSource = filtered;
        CountLabel.Text = $"{filtered.Count} windows";
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
        => ApplyFilter(SearchBox.Text);

    private void PickList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        SelectedProcess = (PickList.SelectedItem as PickerRow)?.Source;
        IsPrimaryButtonEnabled = SelectedProcess != null && !SelectedProcess.AlreadyMonitored;
    }

    private void PickList_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
    {
        if (SelectedProcess != null && !SelectedProcess.AlreadyMonitored)
        {
            _doubleTapConfirmed = true;
            Hide();
        }
    }

    public bool WasConfirmed(ContentDialogResult result)
        => result == ContentDialogResult.Primary || _doubleTapConfirmed;
}
