namespace MapofAgents.Core;

public readonly record struct ThreadInboxHeaderPresentationSnapshot(
    bool UsesTrayFullIcon,
    string TrayMacSymbolName,
    string RefreshMacSymbolName,
    string ExpandedChevronMacSymbolName,
    string CollapsedChevronMacSymbolName,
    string StrokeHex,
    string RefreshHelp,
    string RefreshAccessibilityLabel,
    string ExpandedCollapseHelp,
    string CollapsedCollapseHelp,
    string ExpandedCollapseAccessibilityLabel,
    string CollapsedCollapseAccessibilityLabel,
    double HeaderIconWidth,
    double HeaderIconHeight,
    double StrokeThickness,
    double ActionIconSize,
    double ActionStrokeThickness);

public static class ThreadInboxHeaderPresentation
{
    public const string TrayMacSymbolName = "tray.full";
    public const string RefreshMacSymbolName = "arrow.clockwise";
    public const string ExpandedChevronMacSymbolName = "chevron.up";
    public const string CollapsedChevronMacSymbolName = "chevron.down";
    public const string StrokeHex = "#A7B0BF";
    public const string RefreshHelp = "Refresh thread inbox";
    public const string RefreshAccessibilityLabel = "Refresh thread inbox";
    public const string ExpandedCollapseHelp = "Minimize";
    public const string CollapsedCollapseHelp = "Expand";
    public const string ExpandedCollapseAccessibilityLabel = "Minimize thread inbox";
    public const string CollapsedCollapseAccessibilityLabel = "Expand thread inbox";
    public const double HeaderIconWidth = 17;
    public const double HeaderIconHeight = 15;
    public const double StrokeThickness = 1.25;
    public const double ActionIconSize = 15;
    public const double ActionStrokeThickness = 1.3;

    public static ThreadInboxHeaderPresentationSnapshot Resolve()
    {
        return new ThreadInboxHeaderPresentationSnapshot(
            UsesTrayFullIcon: true,
            TrayMacSymbolName,
            RefreshMacSymbolName,
            ExpandedChevronMacSymbolName,
            CollapsedChevronMacSymbolName,
            StrokeHex,
            RefreshHelp,
            RefreshAccessibilityLabel,
            ExpandedCollapseHelp,
            CollapsedCollapseHelp,
            ExpandedCollapseAccessibilityLabel,
            CollapsedCollapseAccessibilityLabel,
            HeaderIconWidth,
            HeaderIconHeight,
            StrokeThickness,
            ActionIconSize,
            ActionStrokeThickness);
    }
}
