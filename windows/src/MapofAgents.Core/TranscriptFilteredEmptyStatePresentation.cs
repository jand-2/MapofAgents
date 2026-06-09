namespace MapofAgents.Core;

public readonly record struct TranscriptFilteredEmptyStatePresentationSnapshot(
    string Title,
    string ButtonText,
    string MacSymbolName,
    string WindowsGlyph,
    string ButtonMacSymbolName,
    string ButtonWindowsGlyph,
    string BackgroundHex,
    string BorderHex,
    string ForegroundHex,
    double Padding,
    double ContentSpacing,
    double CornerRadius,
    double BorderThickness,
    double IconSize,
    double TitleFontSize,
    double ButtonHorizontalPadding,
    double ButtonVerticalPadding,
    double ButtonContentSpacing,
    double ButtonIconFontSize,
    double ButtonTextFontSize);

public static class TranscriptFilteredEmptyStatePresentation
{
    public const string Title = "No rows match the active filters";
    public const string ButtonText = "Show All Rows";
    public const string MacSymbolName = TranscriptFilterPresentation.MacSymbolName;
    public const string WindowsGlyph = "\uE71C";
    public const string ButtonMacSymbolName = "checklist";
    public const string ButtonWindowsGlyph = "\uE9D5";
    public const string BackgroundHex = "#12697586";
    public const string BorderHex = "#00FFFFFF";
    public const string ForegroundHex = TranscriptFilterPresentation.ForegroundHex;
    public const double Padding = 18;
    public const double ContentSpacing = 10;
    public const double CornerRadius = 8;
    public const double BorderThickness = 0;
    public const double IconSize = TranscriptFilterPresentation.EmptyIconSize;
    public const double TitleFontSize = 14;
    public const double ButtonHorizontalPadding = 9;
    public const double ButtonVerticalPadding = 4;
    public const double ButtonContentSpacing = 6;
    public const double ButtonIconFontSize = 11;
    public const double ButtonTextFontSize = 12;

    public static TranscriptFilteredEmptyStatePresentationSnapshot Resolve()
    {
        return new TranscriptFilteredEmptyStatePresentationSnapshot(
            Title,
            ButtonText,
            MacSymbolName,
            WindowsGlyph,
            ButtonMacSymbolName,
            ButtonWindowsGlyph,
            BackgroundHex,
            BorderHex,
            ForegroundHex,
            Padding,
            ContentSpacing,
            CornerRadius,
            BorderThickness,
            IconSize,
            TitleFontSize,
            ButtonHorizontalPadding,
            ButtonVerticalPadding,
            ButtonContentSpacing,
            ButtonIconFontSize,
            ButtonTextFontSize);
    }
}
