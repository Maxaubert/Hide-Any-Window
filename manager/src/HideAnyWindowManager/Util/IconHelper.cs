using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Media.Imaging;

namespace HideAnyWindowManager.Util;

internal static class IconHelper
{
    /// <summary>Loads the associated icon for a file (typically an exe) and returns it
    /// as a WinUI 3 BitmapImage. Returns null on any failure.</summary>
    public static async Task<BitmapImage?> LoadIconAsync(string filePath)
    {
        if (string.IsNullOrEmpty(filePath) || !File.Exists(filePath))
            return null;
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(filePath);
            if (icon == null) return null;
            using var bitmap = icon.ToBitmap();
            using var ms = new MemoryStream();
            bitmap.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
            ms.Position = 0;
            var bmp = new BitmapImage();
            await bmp.SetSourceAsync(ms.AsRandomAccessStream());
            return bmp;
        }
        catch
        {
            return null;
        }
    }
}
