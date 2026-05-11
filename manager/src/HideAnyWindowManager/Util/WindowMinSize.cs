using System;
using System.Runtime.InteropServices;

namespace HideAnyWindowManager.Util;

internal sealed class WindowMinSize
{
    private readonly IntPtr _hwnd;
    private readonly int _minWidthLogical;
    private readonly int _minHeightLogical;
    private Win32.WndProcDelegate _newWndProc = null!;
    private IntPtr _oldWndProc;

    private WindowMinSize(IntPtr hwnd, int minWidthLogical, int minHeightLogical)
    {
        _hwnd = hwnd;
        _minWidthLogical = minWidthLogical;
        _minHeightLogical = minHeightLogical;
    }

    /// <summary>Subclasses the given window's WndProc to enforce a minimum size in logical pixels.
    /// Call once per window. Keep the returned instance alive (e.g. as a field on the Window) so
    /// the delegate isn't GC'd.</summary>
    public static WindowMinSize Apply(IntPtr hwnd, int minWidthLogical, int minHeightLogical)
    {
        var inst = new WindowMinSize(hwnd, minWidthLogical, minHeightLogical);
        inst._newWndProc = inst.WndProc;
        inst._oldWndProc = Win32.SetWindowLongPtr(hwnd, Win32.GWLP_WNDPROC, Marshal.GetFunctionPointerForDelegate(inst._newWndProc));
        return inst;
    }

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == Win32.WM_GETMINMAXINFO)
        {
            try
            {
                uint dpi = Win32.GetDpiForWindow(hWnd);
                if (dpi == 0) dpi = 96;
                int minW = (int)(_minWidthLogical * dpi / 96.0);
                int minH = (int)(_minHeightLogical * dpi / 96.0);
                var mmi = Marshal.PtrToStructure<Win32.MINMAXINFO>(lParam);
                mmi.ptMinTrackSize.X = minW;
                mmi.ptMinTrackSize.Y = minH;
                Marshal.StructureToPtr(mmi, lParam, true);
            }
            catch { /* fall through to old WndProc */ }
        }
        return Win32.CallWindowProc(_oldWndProc, hWnd, msg, wParam, lParam);
    }
}
