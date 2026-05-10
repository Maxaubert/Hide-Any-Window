using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace HideAnyWindowManager.Services;

public sealed class ServiceController
{
    private const string MutexName = "HideAnyWindow_Service_Running";

    /// <summary>Returns true if the AHK service process is currently holding its named mutex.</summary>
    public bool IsServiceRunning()
    {
        try
        {
            using var existing = Mutex.OpenExisting(MutexName);
            return true;
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            // Mutex exists but we can't open it — treat as running.
            return true;
        }
    }

    /// <summary>Launches the AHK service via AutoHotkey64_UIA.exe. The UIA-signed AHK
    /// auto-elevates without a UAC prompt and gives the script UIAccess privileges.</summary>
    /// <returns>true if launch was attempted; false if the AHK install or script wasn't found.</returns>
    public bool TryStartService(string? scriptPath = null, string? ahkUiaPath = null)
    {
        scriptPath ??= DefaultScriptPath();
        ahkUiaPath ??= DefaultAhkUiaPath();

        bool scriptOk = File.Exists(scriptPath);
        bool ahkOk = File.Exists(ahkUiaPath);
        Log($"TryStartService probed: ahkUia={ahkUiaPath} (exists={ahkOk})  script={scriptPath} (exists={scriptOk})");

        if (!scriptOk || !ahkOk)
        {
            Log("TryStartService aborting — one or both paths missing");
            return false;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = ahkUiaPath,
                Arguments = "\"" + scriptPath + "\"",
                UseShellExecute = true,   // required for UIAccess auto-elevation of AutoHotkey64_UIA.exe
            };
            var proc = Process.Start(psi);
            Log($"TryStartService Process.Start returned proc={proc?.Id.ToString() ?? "null"}");
            return proc != null;
        }
        catch (Exception ex)
        {
            Log($"TryStartService Process.Start threw: {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    private static void Log(string msg)
    {
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "HideAnyWindow");
            Directory.CreateDirectory(dir);
            var line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " | " + msg + "\r\n";
            File.AppendAllText(Path.Combine(dir, "manager.log"), line);
        }
        catch { /* swallow logging errors */ }
    }

    public static string DefaultAhkUiaPath()
        => @"C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe";

    public static string DefaultScriptPath()
    {
        // Walk up from BaseDirectory looking for a "service\main.ahk" sibling.
        // Works for any build config (Debug/Release/publish) and for deployed
        // layouts where service/ sits next to the manager binary.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            var probe = Path.Combine(dir.FullName, "service", "main.ahk");
            if (File.Exists(probe))
                return probe;
            dir = dir.Parent;
        }
        // Fallback: return the closest-best guess so error message is informative.
        return Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, @"..\service\main.ahk"));
    }
}
