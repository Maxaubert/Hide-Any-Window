using System.Collections.Generic;

namespace HideAnyWindowManager.Models;

public sealed class Config
{
    public int SchemaVersion { get; set; } = 1;
    public string ServiceState { get; set; } = "running";
    public List<Rule> Rules { get; set; } = new();
}
