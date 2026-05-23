using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using HideAnyWindowManager.Models;
using HideAnyWindowManager.Util;

namespace HideAnyWindowManager.Services;

public sealed class ProcessEnumerator
{
    /// <summary>Enumerates all visible top-level (un-owned) windows, dedupes by owning process exe,
    /// and returns one entry per exe with a friendly name (the first window's title or the exe name).</summary>
    public IReadOnlyList<WindowedProcessInfo> EnumerateWindowedProcesses(IReadOnlyCollection<string> alreadyMonitoredExes)
    {
        var byExe = new Dictionary<string, WindowedProcessInfo>(StringComparer.OrdinalIgnoreCase);
        var monitoredSet = new HashSet<string>(alreadyMonitoredExes, StringComparer.OrdinalIgnoreCase);

        Win32.EnumWindows((hWnd, _) =>
        {
            try
            {
                if (!Win32.IsWindowVisible(hWnd)) return true;
                if (Win32.GetWindow(hWnd, Win32.GW_OWNER) != IntPtr.Zero) return true; // skip owned (e.g. dialogs)
                if (Win32.GetWindowTextLength(hWnd) == 0) return true; // skip windows with no title (system, hidden helpers)

                Win32.GetWindowThreadProcessId(hWnd, out uint pid);
                if (pid == 0) return true;

                var (exe, fullPath) = GetProcessImage(pid);
                if (string.IsNullOrEmpty(exe)) return true;
                if (string.Equals(exe, "hideanywindowmanager.exe", StringComparison.OrdinalIgnoreCase))
                    return true;  // never offer to hide ourselves
                if (monitoredSet.Contains(exe)) return true;  // already in rules, hide from picker

                if (!byExe.ContainsKey(exe))
                {
                    byExe[exe] = new WindowedProcessInfo
                    {
                        Exe = exe,
                        Name = GetFriendlyName(fullPath, exe),
                        FullPath = fullPath,
                    };
                }
            }
            catch
            {
                // Never let an exception escape into the native EnumWindows dispatcher:
                // unwinding across the managed/native boundary is undefined behavior and
                // can crash the process. Skip this window and keep enumerating.
            }
            return true;
        }, IntPtr.Zero);

        return byExe.Values.OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static (string exe, string fullPath) GetProcessImage(uint pid)
    {
        var hProc = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (hProc == IntPtr.Zero) return ("", "");
        try
        {
            int capacity = 1024;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                var buf = new StringBuilder(capacity);
                uint size = (uint)buf.Capacity;
                if (Win32.QueryFullProcessImageNameW(hProc, 0, buf, ref size))
                {
                    var fullPath = buf.ToString();
                    return (Path.GetFileName(fullPath).ToLowerInvariant(), fullPath);
                }
                // ERROR_INSUFFICIENT_BUFFER (122): grow and retry. Any other error: give up.
                if (Marshal.GetLastWin32Error() != 122) break;
                capacity *= 4;
            }
            return ("", "");
        }
        finally
        {
            Win32.CloseHandle(hProc);
        }
    }

    private static string GetFriendlyName(string fullPath, string fallback)
    {
        try
        {
            var info = FileVersionInfo.GetVersionInfo(fullPath);
            var desc = info.FileDescription;
            if (!string.IsNullOrWhiteSpace(desc))
                return desc;
        }
        catch { /* falls through to fallback */ }
        return fallback;
    }
}
