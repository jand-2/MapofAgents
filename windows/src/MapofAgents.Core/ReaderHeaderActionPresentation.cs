namespace MapofAgents.Core;

public readonly record struct ReaderHeaderActionPresentationSnapshot(
    string ClearMacSymbolName,
    string ClearGlyph,
    string ClearLabel,
    string ClearForegroundHex,
    string ClearCircleStrokeHex,
    double ClearIconDiameter,
    double ClearGlyphFontSize);

public static class ReaderHeaderActionPresentation
{
    public const string ClearMacSymbolName = "xmark.circle";
    public const string ClearGlyph = "\uE711";
    public const string ClearLabel = "Clear";
    public const string ClearForegroundHex = "#A7B0BF";
    public const string ClearCircleStrokeHex = "#A7B0BF";
    public const double ClearIconDiameter = 13;
    public const double ClearGlyphFontSize = 7;

    public static ReaderHeaderActionPresentationSnapshot ResolveClear()
    {
        return new ReaderHeaderActionPresentationSnapshot(
            ClearMacSymbolName,
            ClearGlyph,
            ClearLabel,
            ClearForegroundHex,
            ClearCircleStrokeHex,
            ClearIconDiameter,
            ClearGlyphFontSize);
    }
}
