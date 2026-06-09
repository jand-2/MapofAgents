namespace MapofAgents.Core;

public readonly record struct ToolbarSearchPresentationSnapshot(
    string MacSymbolName,
    string StyleKey,
    string StrokeHex,
    string ToolTip,
    double IconSize,
    double StrokeThickness);

public static class ToolbarSearchPresentation
{
    public const string MacSymbolName = "magnifyingglass";
    public const string ActiveStyleKey = "ToolbarPlainButtonStyle";
    public const string InactiveStyleKey = "ToolbarPlainButtonStyle";
    public const string StrokeHex = "#D7DCE5";
    public const string ToolTip = "Search the thread inbox";
    public const double IconSize = 15;
    public const double StrokeThickness = 1.55;

    public static ToolbarSearchPresentationSnapshot Resolve(bool isSearching)
    {
        return new ToolbarSearchPresentationSnapshot(
            MacSymbolName,
            ActiveStyleKey,
            StrokeHex,
            ToolTip,
            IconSize,
            StrokeThickness);
    }
}
