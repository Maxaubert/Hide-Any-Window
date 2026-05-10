using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
            if (!Win32.IsWindowVisible(hWnd)) return true;
            if (Win32.GetWindow(hWnd, Win32.GW_OWNER) != IntPtr.Zero) return true; // skip owned (e.g. dialogs)
            int len = Win32.GetWindowTextLength(hWnd);
            if (len == 0) return true; // skip windows with no title (system, hidden helpers)

            var titleBuf = new StringBuilder(len + 1);
            Win32.GetWindowText(hWnd, titleBuf, titleBuf.Capacity);
            var title = titleBuf.ToString();

            Win32.GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == 0) return true;

            var (exe, fullPath) = GetProcessImage(pid);
            if (string.IsNullOrEmpty(exe)) return true;

            if (!byExe.ContainsKey(exe))
            {
                byExe[exe] = new WindowedProcessInfo
                {
                    Exe = exe,
                    Name = string.IsNullOrEmpty(title) ? exe : title,
                    FullPath = fullPath,
                    AlreadyMonitored = monitoredSet.Contains(exe),
                };
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
            var buf = new StringBuilder(1024);
            uint size = (uint)buf.Capacity;
            if (!Win32.QueryFullProcessImageNameW(hProc, 0, buf, ref size))
                return ("", "");
            var fullPath = buf.ToString();
            return (Path.GetFileName(fullPath).ToLowerInvariant(), fullPath);
        }
        finally
        {
            Win32.CloseHandle(hProc);
        }
    }
}
