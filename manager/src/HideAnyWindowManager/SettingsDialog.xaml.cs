using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace HideAnyWindowManager;

public sealed partial class SettingsDialog : ContentDialog
{
    private bool _initializing = true;

    public SettingsDialog()
    {
        InitializeComponent();
        AutostartSwitch.IsOn = App.AutostartManager.IsEnabled();
        _initializing = false;
    }

    private void AutostartSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_initializing) return;
        if (AutostartSwitch.IsOn)
            App.AutostartManager.TryEnable();
        else
            App.AutostartManager.TryDisable();
    }
}
