using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;
using Microsoft.UI.Xaml.Media.Imaging;

namespace HideAnyWindowManager.ViewModels;

public sealed class PickerRow : ObservableObject
{
    private BitmapImage? _icon;

    public WindowedProcessInfo Source { get; }
    public string Name => Source.Name;
    public string Exe => Source.Exe;
    public bool AlreadyMonitored => Source.AlreadyMonitored;
    public string AlreadyMonitoredAnnotation => Source.AlreadyMonitoredAnnotation;

    public BitmapImage? Icon
    {
        get => _icon;
        set => SetField(ref _icon, value);
    }

    public PickerRow(WindowedProcessInfo source) { Source = source; }
}
