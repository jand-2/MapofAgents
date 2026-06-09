namespace MapofAgents.Core;

public readonly record struct ThreadHeaderActionPresentationSnapshot(
    string ForegroundHex,
    string BackgroundHex,
    double HitTargetSize,
    double IconFontSize,
    double BorderThickness,
    string RefreshWindowsGlyph,
    string CloseWindowsGlyph,
    string RefreshToolTip,
    string RefreshAccessibilityName,
    string CloseToolTip,
    string CloseAccessibilityName);

public static class ThreadHeaderActionPresentation
{
    public const string ForegroundHex = "#A7B0BF";
    public const string BackgroundHex = "#00FFFFFF";
    public const double HitTargetSize = 24;
    public const double IconFontSize = 12;
    public const double BorderThickness = 0;
    public const string RefreshWindowsGlyph = "\uE72C";
    public const string CloseWindowsGlyph = "\uE711";
    public const string RefreshToolTip = "Refresh";
    public const string RefreshAccessibilityName = "Refresh transcript";
    public const string CloseToolTip = "Close";
    public const string CloseAccessibilityName = "Close chat";

    public static ThreadHeaderActionPresentationSnapshot Resolve()
    {
        return new ThreadHeaderActionPresentationSnapshot(
            ForegroundHex,
            BackgroundHex,
            HitTargetSize,
            IconFontSize,
            BorderThickness,
            RefreshWindowsGlyph,
            CloseWindowsGlyph,
            RefreshToolTip,
            RefreshAccessibilityName,
            CloseToolTip,
            CloseAccessibilityName);
    }
}
