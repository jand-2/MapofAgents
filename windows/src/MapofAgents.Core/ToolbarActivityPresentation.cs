namespace MapofAgents.Core;

public readonly record struct ToolbarActivityPresentationSnapshot(
    string MacSymbolName,
    string StrokeHex,
    string BadgeHex,
    string ToolTip,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double BadgeSize,
    double BadgeX,
    double BadgeY,
    string AccessibilityName);

public static class ToolbarActivityPresentation
{
    public const string MacSymbolName = "bell.badge";
    public const string StrokeHex = "#D7DCE5";
    public const string BadgeHex = "#D7DCE5";
    public const string ToolTip = "Show recent notifications";
    public const double IconWidth = 16;
    public const double IconHeight = 15;
    public const double StrokeThickness = 1.1;
    public const double BadgeSize = 5;
    public const double BadgeX = 11;
    public const double BadgeY = 1;
    public const string AccessibilityName = "Activity";

    public static ToolbarActivityPresentationSnapshot Resolve()
    {
        return new ToolbarActivityPresentationSnapshot(
            MacSymbolName,
            StrokeHex,
            BadgeHex,
            ToolTip,
            IconWidth,
            IconHeight,
            StrokeThickness,
            BadgeSize,
            BadgeX,
            BadgeY,
            AccessibilityName);
    }
}
