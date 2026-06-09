namespace MapofAgents.Core;

public readonly record struct WindowStartupBounds(int X, int Y, int Width, int Height);

public readonly record struct WindowMinimumTrackSize(int Width, int Height);

public static class WindowStartupPlacement
{
    public const int PreferredWidth = 1380;
    public const int PreferredHeight = 860;
    public const int MinimumWidth = 980;
    public const int MinimumHeight = 640;
    public const int DefaultDpi = 96;

    public static WindowStartupBounds CenterInWorkArea(
        int workAreaX,
        int workAreaY,
        int workAreaWidth,
        int workAreaHeight,
        int preferredWidth,
        int preferredHeight)
    {
        var width = Math.Clamp(preferredWidth, 1, Math.Max(1, workAreaWidth));
        var height = Math.Clamp(preferredHeight, 1, Math.Max(1, workAreaHeight));
        var x = workAreaX + Math.Max(0, (workAreaWidth - width) / 2);
        var y = workAreaY + Math.Max(0, (workAreaHeight - height) / 2);

        return new WindowStartupBounds(x, y, width, height);
    }

    public static WindowMinimumTrackSize MinimumTrackSizeForDpi(uint dpi)
    {
        var effectiveDpi = dpi == 0 ? DefaultDpi : dpi;
        var scale = (double)effectiveDpi / DefaultDpi;
        return new WindowMinimumTrackSize(
            Math.Max(1, (int)Math.Ceiling(MinimumWidth * scale)),
            Math.Max(1, (int)Math.Ceiling(MinimumHeight * scale)));
    }
}
