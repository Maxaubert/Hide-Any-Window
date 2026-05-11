using System.Diagnostics;

namespace HideAnyWindowManager.Services;

public sealed class AutostartManager
{
    private const string TaskName = "HideAnyWindowService";

    /// <summary>True if a Task Scheduler at-logon task for the service exists.</summary>
    public bool IsEnabled()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("/Query");
            psi.ArgumentList.Add("/TN");
            psi.ArgumentList.Add(TaskName);
            var proc = Process.Start(psi);
            if (proc == null) return false;
            proc.WaitForExit(5000);
            return proc.ExitCode == 0;
        }
        catch { return false; }
    }

    /// <summary>Creates an at-logon task that launches AutoHotkey64_UIA.exe with the service script.
    /// Runs with highest privileges (no UAC prompt at logon for the elevated AHK service). Overwrites
    /// any existing task with the same name.</summary>
    public bool TryEnable()
    {
        try
        {
            var script = ServiceController.DefaultScriptPath();
            var ahkUia = ServiceController.DefaultAhkUiaPath();
            // schtasks /TR expects ONE argument: the full command line. Embed quotes around each path
            // so the spawned process sees quoted args.
            var taskRun = string.IsNullOrEmpty(script)
                ? $"\"{ahkUia}\""
                : $"\"{ahkUia}\" \"{script}\"";
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("/Create");
            psi.ArgumentList.Add("/TN");
            psi.ArgumentList.Add(TaskName);
            psi.ArgumentList.Add("/SC");
            psi.ArgumentList.Add("ONLOGON");
            psi.ArgumentList.Add("/RL");
            psi.ArgumentList.Add("HIGHEST");
            psi.ArgumentList.Add("/TR");
            psi.ArgumentList.Add(taskRun);
            psi.ArgumentList.Add("/F");
            var proc = Process.Start(psi);
            if (proc == null) return false;
            proc.WaitForExit(10000);
            return proc.ExitCode == 0;
        }
        catch { return false; }
    }

    /// <summary>Removes the at-logon task. Idempotent (returns true if already absent).</summary>
    public bool TryDisable()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            psi.ArgumentList.Add("/Delete");
            psi.ArgumentList.Add("/TN");
            psi.ArgumentList.Add(TaskName);
            psi.ArgumentList.Add("/F");
            var proc = Process.Start(psi);
            if (proc == null) return true;
            proc.WaitForExit(5000);
            // schtasks returns 0 on success and 1 if the task didn't exist — both fine for our purposes.
            return true;
        }
        catch { return false; }
    }
}
