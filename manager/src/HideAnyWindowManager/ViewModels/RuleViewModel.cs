using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.ViewModels;

public sealed class RuleViewModel : ObservableObject
{
    private bool _enabled;
    public string Id { get; }
    public string Exe { get; }
    public string Name { get; set; }

    public bool Enabled
    {
        get => _enabled;
        set => SetField(ref _enabled, value);
    }

    /// <summary>First letter of Name, used for the placeholder square icon.</summary>
    public string Initial => string.IsNullOrEmpty(Name) ? "?" : Name.Substring(0, 1).ToUpperInvariant();

    public RuleViewModel(Rule r)
    {
        Id = r.Id; Exe = r.Exe; Name = r.Name; _enabled = r.Enabled;
    }

    public Rule ToModel() => new() { Id = Id, Exe = Exe, Name = Name, Enabled = Enabled };
}
