using System;
using System.IO;

namespace HideAnyWindowManager.Util;

internal static class ManagerLog
{
    public static void Write(string msg)
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
}
