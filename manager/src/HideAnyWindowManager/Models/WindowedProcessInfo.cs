namespace HideAnyWindowManager.Models;

/// <summary>One row in the Add picker — a process that has at least one visible top-level window.</summary>
public sealed class WindowedProcessInfo
{
    public string Exe { get; set; } = "";        // basename, e.g. "magnify.exe"
    public string Name { get; set; } = "";       // friendly name, e.g. "Magnifier"
    public string FullPath { get; set; } = "";   // for tooltip / debugging
    public bool AlreadyMonitored { get; set; }   // true if Exe is already in current Config.Rules
}
