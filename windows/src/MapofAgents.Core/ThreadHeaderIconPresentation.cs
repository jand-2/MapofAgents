namespace MapofAgents.Core;

public readonly record struct ThreadHeaderIconPresentationSnapshot(
    string HeaderMacSymbolName,
    string KindMacSymbolName,
    string HeaderGlyph,
    bool UsesHeaderThreadPairIcon,
    string KindGlyph,
    string HeaderForegroundHex,
    string HeaderBackgroundHex,
    string KindForegroundHex,
    string KindBackgroundHex,
    double HeaderSurfaceSize,
    double HeaderSurfaceCornerRadius,
    double HeaderIconGridWidth,
    double HeaderIconGridHeight,
    double HeaderGlyphFontSize,
    double HeaderPairBackGlyphFontSize,
    double HeaderPairFrontGlyphFontSize,
    double HeaderPairStrokeThickness,
    double HeaderPairBackOpacity);

public static class ThreadHeaderIconPresentation
{
    public const string ThreadHeaderMacSymbolName = "bubble.left.and.bubble.right";
    public const string ThreadKindMacSymbolName = "bubble.left";
    public const string SubagentMacSymbolName = "person.2";
    public const string ThreadGlyph = "\uE8F2";
    public const string SubagentGlyph = "\uE716";
    public const string BlueHex = "#0A84FF";
    public const string PurpleHex = "#BF5AF2";
    public const string SecondaryHex = "#A7B0BF";
    public const string ThreadHeaderBackgroundHex = "#1F0A84FF";
    public const string SubagentBackgroundHex = "#1FBF5AF2";
    public const string ThreadKindBackgroundHex = "#1AA7B0BF";
    public const string SubagentKindBackgroundHex = "#1ABF5AF2";
    public const double HeaderSurfaceSize = 26;
    public const double HeaderSurfaceCornerRadius = 6;
    public const double HeaderIconGridWidth = 18;
    public const double HeaderIconGridHeight = 16;
    public const double HeaderGlyphFontSize = 13;
    public const double HeaderPairBackGlyphFontSize = 11;
    public const double HeaderPairFrontGlyphFontSize = 12;
    public const double HeaderPairStrokeThickness = 1.15;
    public const double HeaderPairBackOpacity = 0.72;

    public static ThreadHeaderIconPresentationSnapshot Resolve(bool isSubagent)
    {
        return isSubagent
            ? new ThreadHeaderIconPresentationSnapshot(
                SubagentMacSymbolName,
                SubagentMacSymbolName,
                SubagentGlyph,
                UsesHeaderThreadPairIcon: false,
                SubagentGlyph,
                PurpleHex,
                SubagentBackgroundHex,
                PurpleHex,
                SubagentKindBackgroundHex,
                HeaderSurfaceSize,
                HeaderSurfaceCornerRadius,
                HeaderIconGridWidth,
                HeaderIconGridHeight,
                HeaderGlyphFontSize,
                HeaderPairBackGlyphFontSize,
                HeaderPairFrontGlyphFontSize,
                HeaderPairStrokeThickness,
                HeaderPairBackOpacity)
            : new ThreadHeaderIconPresentationSnapshot(
                ThreadHeaderMacSymbolName,
                ThreadKindMacSymbolName,
                ThreadGlyph,
                UsesHeaderThreadPairIcon: true,
                ThreadGlyph,
                BlueHex,
                ThreadHeaderBackgroundHex,
                SecondaryHex,
                ThreadKindBackgroundHex,
                HeaderSurfaceSize,
                HeaderSurfaceCornerRadius,
                HeaderIconGridWidth,
                HeaderIconGridHeight,
                HeaderGlyphFontSize,
                HeaderPairBackGlyphFontSize,
                HeaderPairFrontGlyphFontSize,
                HeaderPairStrokeThickness,
                HeaderPairBackOpacity);
    }
}
