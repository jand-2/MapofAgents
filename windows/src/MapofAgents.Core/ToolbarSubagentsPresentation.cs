namespace MapofAgents.Core;

public readonly record struct ToolbarSubagentsPresentationSnapshot(
    string MacSymbolName,
    string StyleKey,
    string IconHex,
    string SlashHex,
    bool ShowsSlash,
    string ToolTip,
    string AccessibilityName,
    double IconWidth,
    double IconHeight,
    double SlashStrokeThickness);

public static class ToolbarSubagentsPresentation
{
    public const string VisibleMacSymbolName = "person.2.fill";
    public const string HiddenMacSymbolName = "person.2.slash";
    public const string ActiveStyleKey = "ToolbarPurpleButtonStyle";
    public const string InactiveStyleKey = "ToolbarButtonStyle";
    public const string ActiveIconHex = "#FFDDB8FF";
    public const string InactiveIconHex = "#D7DCE5";
    public const string ActiveToolTip = "Hide subagent nodes and lines";
    public const string InactiveToolTip = "Show subagent nodes and lines";
    public const string AccessibilityName = "Subagents";
    public const double IconWidth = 17;
    public const double IconHeight = 15;
    public const double SlashStrokeThickness = 1.8;

    public static ToolbarSubagentsPresentationSnapshot Resolve(bool showsSubagents)
    {
        return new ToolbarSubagentsPresentationSnapshot(
            showsSubagents ? VisibleMacSymbolName : HiddenMacSymbolName,
            showsSubagents ? ActiveStyleKey : InactiveStyleKey,
            showsSubagents ? ActiveIconHex : InactiveIconHex,
            showsSubagents ? ActiveIconHex : InactiveIconHex,
            ShowsSlash: !showsSubagents,
            showsSubagents ? ActiveToolTip : InactiveToolTip,
            AccessibilityName,
            IconWidth,
            IconHeight,
            SlashStrokeThickness);
    }
}
