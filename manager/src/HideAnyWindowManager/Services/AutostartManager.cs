using System.Diagnostics;

namespace HideAnyWindowManager.Services;

public sealed class AutostartManager
{
    private const string TaskName = "HideAnyWindowService";
    public const string StartServiceArg = "--start-service";

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

    /// <summary>Creates an at-logon task that launches the manager with --start-service.
    /// The manager (requireAdministrator, no uiAccess) launches cleanly via CreateProcess
    /// with the user's elevated token; it then ShellExecutes the uiAccess service exe,
    /// which AppInfo silently auto-elevates. Pointing the task directly at the uiAccess
    /// service exe fails with ERROR_ELEVATION_REQUIRED (740) because CreateProcess cannot
    /// launch uiAccess binaries — only ShellExecute can. Overwrites any existing task.</summary>
    public bool TryEnable()
    {
        try
        {
            var managerExe = ManagerExePath();
            if (string.IsNullOrEmpty(managerExe)) return false;
            // schtasks /TR expects ONE argument: the full command line. Quote the path so
            // the spawned process sees it as a single arg.
            var taskRun = $"\"{managerExe}\" {StartServiceArg}";
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

    private static string ManagerExePath()
    {
        try { return Process.GetCurrentProcess().MainModule?.FileName ?? ""; }
        catch { return ""; }
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
