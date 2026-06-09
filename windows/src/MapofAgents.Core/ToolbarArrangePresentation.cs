namespace MapofAgents.Core;

public readonly record struct ToolbarArrangePresentationSnapshot(
    bool UsesRectangleGroupIcon,
    string StrokeHex,
    string ToolTip,
    string AccessibilityName);

public static class ToolbarArrangePresentation
{
    public const string StrokeHex = "#D7DCE5";
    public const string ToolTip = "Arrange machines, folders, and threads into default zones";
    public const string AccessibilityName = "Arrange";

    public static ToolbarArrangePresentationSnapshot Resolve()
    {
        return new ToolbarArrangePresentationSnapshot(
            UsesRectangleGroupIcon: true,
            StrokeHex,
            ToolTip,
            AccessibilityName);
    }
}
