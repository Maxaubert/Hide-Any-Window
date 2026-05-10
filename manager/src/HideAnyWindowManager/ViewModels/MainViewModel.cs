using System.Collections.ObjectModel;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private bool _isServiceRunning;
    private RuleViewModel? _selectedRule;

    public ObservableCollection<RuleViewModel> Rules { get; } = new();

    public bool IsServiceRunning
    {
        get => _isServiceRunning;
        set { SetField(ref _isServiceRunning, value); Raise(nameof(StatusText)); Raise(nameof(ServiceButtonText)); }
    }

    public RuleViewModel? SelectedRule
    {
        get => _selectedRule;
        set { SetField(ref _selectedRule, value); Raise(nameof(CanRemove)); }
    }

    public bool CanRemove => SelectedRule != null;
    public string StatusText => IsServiceRunning ? "Service running" : "Service stopped";
    public string ServiceButtonText => IsServiceRunning ? "Stop service" : "Start service";

    public void LoadFrom(Config cfg)
    {
        Rules.Clear();
        foreach (var r in cfg.Rules) Rules.Add(new RuleViewModel(r));
    }

    public Config ToConfig(string serviceState)
    {
        var cfg = new Config { ServiceState = serviceState };
        foreach (var r in Rules) cfg.Rules.Add(r.ToModel());
        return cfg;
    }
}
