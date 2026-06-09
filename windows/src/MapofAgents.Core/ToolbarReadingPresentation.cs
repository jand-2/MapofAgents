namespace MapofAgents.Core;

public readonly record struct ToolbarReadingPresentationSnapshot(
    string MacSymbolName,
    string StyleKey,
    string StrokeHex,
    string ToolTip,
    string Title,
    double IconWidth,
    double IconHeight,
    double StrokeThickness);

public static class ToolbarReadingPresentation
{
    public const string MacSymbolName = "rectangle.split.3x1";
    public const string StyleKey = "ToolbarButtonStyle";
    public const string StrokeHex = "#D7DCE5";
    public const string ToolTip = "Open focused chat reading mode";
    public const double IconWidth = 15;
    public const double IconHeight = 14;
    public const double StrokeThickness = 1;

    public static ToolbarReadingPresentationSnapshot Resolve(int readingThreadCount)
    {
        var title = readingThreadCount > 0
            ? $"Reader {readingThreadCount}"
            : "Reader";

        return new ToolbarReadingPresentationSnapshot(
            MacSymbolName,
            StyleKey,
            StrokeHex,
            ToolTip,
            title,
            IconWidth,
            IconHeight,
            StrokeThickness);
    }
}
