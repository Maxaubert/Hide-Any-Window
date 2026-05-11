namespace HideAnyWindowManager.Models;

public sealed class Rule
{
    public string Id { get; set; } = "";
    public string Exe { get; set; } = "";
    public string Path { get; set; } = "";
    public string Name { get; set; } = "";
    public bool Enabled { get; set; } = true;

    /// <summary>Generates a stable id from an exe name, e.g. "magnify.exe" -&gt; "magnify-exe".</summary>
    public static string IdFromExe(string exe)
        => exe.ToLowerInvariant().Replace('.', '-');
}
