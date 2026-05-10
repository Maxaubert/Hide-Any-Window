using System.Collections.Generic;
using System.Linq;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace HideAnyWindowManager;

public sealed partial class AddPickerDialog : ContentDialog
{
    private readonly List<WindowedProcessInfo> _all;
    public WindowedProcessInfo? SelectedProcess { get; private set; }

    public AddPickerDialog(ProcessEnumerator enumerator, IReadOnlyCollection<string> alreadyMonitoredExes)
    {
        InitializeComponent();
        _all = enumerator.EnumerateWindowedProcesses(alreadyMonitoredExes).ToList();
        ApplyFilter("");
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
        SelectedProcess = PickList.SelectedItem as WindowedProcessInfo;
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

    private bool _doubleTapConfirmed;
    /// <summary>True if user accepted via primary button OR double-tap.</summary>
    public bool WasConfirmed(ContentDialogResult result) => result == ContentDialogResult.Primary || _doubleTapConfirmed;
}
