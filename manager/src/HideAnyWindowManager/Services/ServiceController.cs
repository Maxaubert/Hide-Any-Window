using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.Services;

public sealed class ServiceController
{
    /// <summary>The named mutex the running service holds. Shared IPC contract with the
    /// AHK service — must stay in sync with the name used in service/main.ahk.</summary>
    public const string DefaultMutexName = "HideAnyWindow_Service_Running";

    private readonly string _mutexName;

    /// <param name="mutexName">Override the mutex name (used by tests for isolation);
    /// defaults to the production <see cref="DefaultMutexName"/>.</param>
    public ServiceController(string? mutexName = null) => _mutexName = mutexName ?? DefaultMutexName;

    /// <summary>Returns true if the AHK service process is currently holding its named mutex.</summary>
    public bool IsServiceRunning()
    {
        try
        {
            using var existing = Mutex.OpenExisting(_mutexName);
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

        bool ahkOk = File.Exists(ahkUiaPath);
        bool scriptOk = string.IsNullOrEmpty(scriptPath) || File.Exists(scriptPath);
        ManagerLog.Write($"TryStartService probed: ahk={ahkUiaPath} (exists={ahkOk})  script={scriptPath} (skip-if-empty, exists={scriptOk})");

        if (!ahkOk || !scriptOk)
        {
            ManagerLog.Write("TryStartService aborting — required path missing");
            return false;
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = ahkUiaPath,
                Arguments = string.IsNullOrEmpty(scriptPath) ? "" : "\"" + scriptPath + "\"",
                UseShellExecute = true,
            };
            var proc = Process.Start(psi);
            ManagerLog.Write($"TryStartService Process.Start returned proc={proc?.Id.ToString() ?? "null"}");
            return proc != null;
        }
        catch (Exception ex)
        {
            ManagerLog.Write($"TryStartService Process.Start threw: {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    public static string DefaultAhkUiaPath()
    {
        // Production: HideAnyWindowService.exe sits next to the manager exe.
        var sibling = System.IO.Path.Combine(System.AppContext.BaseDirectory, "HideAnyWindowService.exe");
        if (System.IO.File.Exists(sibling))
            return sibling;
        // Dev fallback: AutoHotkey64_UIA.exe from a system AHK install.
        return @"C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe";
    }

    public static string DefaultScriptPath()
    {
        // Production: HideAnyWindowService.exe takes no script argument (script embedded).
        var sibling = System.IO.Path.Combine(System.AppContext.BaseDirectory, "HideAnyWindowService.exe");
        if (System.IO.File.Exists(sibling))
            return "";   // signal: no script argument needed
        // Dev fallback: walk up to find service\main.ahk.
        var dir = new System.IO.DirectoryInfo(System.AppContext.BaseDirectory);
        while (dir != null)
        {
            var probe = System.IO.Path.Combine(dir.FullName, "service", "main.ahk");
            if (System.IO.File.Exists(probe))
                return probe;
            dir = dir.Parent;
        }
        return System.IO.Path.GetFullPath(System.IO.Path.Combine(System.AppContext.BaseDirectory, @"..\service\main.ahk"));
    }
}
