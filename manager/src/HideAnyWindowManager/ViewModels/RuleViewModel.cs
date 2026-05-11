using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace HideAnyWindowManager.ViewModels;

public sealed class RuleViewModel : ObservableObject
{
    private bool _enabled;
    private BitmapImage? _icon;

    public string Id { get; }
    public string Exe { get; }
    public string Path { get; }
    public string Name { get; set; }

    public bool Enabled
    {
        get => _enabled;
        set => SetField(ref _enabled, value);
    }

    public BitmapImage? Icon
    {
        get => _icon;
        set
        {
            SetField(ref _icon, value);
            Raise(nameof(IconVisibility));
            Raise(nameof(PlaceholderVisibility));
        }
    }

    public Visibility IconVisibility => _icon != null ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PlaceholderVisibility => _icon == null ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>First letter of Name, used for the placeholder square icon.</summary>
    public string Initial => string.IsNullOrEmpty(Name) ? "?" : Name.Substring(0, 1).ToUpperInvariant();

    public RuleViewModel(Rule r)
    {
        Id = r.Id;
        Exe = r.Exe;
        Path = r.Path;
        Name = r.Name;
        _enabled = r.Enabled;
    }

    public Rule ToModel() => new() { Id = Id, Exe = Exe, Path = Path, Name = Name, Enabled = Enabled };
}
