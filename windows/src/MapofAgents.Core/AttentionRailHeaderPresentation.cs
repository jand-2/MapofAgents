namespace MapofAgents.Core;

public readonly record struct AttentionRailHeaderPresentationSnapshot(
    string MacSymbolName,
    string StrokeHex,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double ExclamationLineTop,
    double ExclamationLineBottom,
    double ExclamationDotSize,
    string AccessibilityName);

public static class AttentionRailHeaderPresentation
{
    public const string MacSymbolName = "exclamationmark.bubble";
    public const string StrokeHex = "#A7B0BF";
    public const double IconWidth = 17;
    public const double IconHeight = 16;
    public const double StrokeThickness = 1.25;
    public const double ExclamationLineTop = 4.2;
    public const double ExclamationLineBottom = 7.6;
    public const double ExclamationDotSize = 1.4;
    public const string AccessibilityName = "Needs Attention";

    public static AttentionRailHeaderPresentationSnapshot Resolve()
    {
        return new AttentionRailHeaderPresentationSnapshot(
            MacSymbolName,
            StrokeHex,
            IconWidth,
            IconHeight,
            StrokeThickness,
            ExclamationLineTop,
            ExclamationLineBottom,
            ExclamationDotSize,
            AccessibilityName);
    }
}
