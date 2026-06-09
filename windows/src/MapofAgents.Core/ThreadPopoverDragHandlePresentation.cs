namespace MapofAgents.Core;

public readonly record struct ThreadPopoverDragHandlePresentationSnapshot(
    string MacSymbolName,
    string ForegroundHex,
    double HitTargetSize,
    double IconWidth,
    double IconHeight,
    double LineWidth,
    double LineHeight,
    double LineRadius,
    double TopLineOffset,
    double MiddleLineOffset,
    double BottomLineOffset,
    string ToolTip,
    string AccessibilityName);

public static class ThreadPopoverDragHandlePresentation
{
    public const string MacSymbolName = "line.3.horizontal";
    public const string ForegroundHex = "#8F9BAA";
    public const double HitTargetSize = 28;
    public const double IconWidth = 14;
    public const double IconHeight = 14;
    public const double LineWidth = 12;
    public const double LineHeight = 1.4;
    public const double LineRadius = 0.7;
    public const double TopLineOffset = 2;
    public const double MiddleLineOffset = 6.3;
    public const double BottomLineOffset = 10.6;
    public const string ToolTip = "Drag chat";
    public const string AccessibilityName = "Drag chat";

    public static ThreadPopoverDragHandlePresentationSnapshot Resolve()
    {
        return new ThreadPopoverDragHandlePresentationSnapshot(
            MacSymbolName,
            ForegroundHex,
            HitTargetSize,
            IconWidth,
            IconHeight,
            LineWidth,
            LineHeight,
            LineRadius,
            TopLineOffset,
            MiddleLineOffset,
            BottomLineOffset,
            ToolTip,
            AccessibilityName);
    }
}
