namespace MapofAgents.Core;

public readonly record struct TranscriptErrorPresentationSnapshot(
    string Title,
    string MacSymbolName,
    string WindowsGlyph,
    string BackgroundHex,
    string BorderHex,
    string IconForegroundHex,
    string TitleForegroundHex,
    string DetailForegroundHex,
    string RetryLabel,
    string UseCachedLabel,
    double Padding,
    double CornerRadius,
    double BorderThickness,
    double ContentSpacing,
    double HeaderColumnSpacing,
    double TextStackSpacing,
    double ActionSpacing,
    double IconTopMargin,
    double IconFontSize,
    double TitleFontSize,
    double DetailFontSize,
    double ButtonHorizontalPadding,
    double ButtonVerticalPadding,
    double ButtonFontSize,
    int DetailMaxLines);

public static class TranscriptErrorPresentation
{
    public const string Title = "Transcript unavailable";
    public const string MacSymbolName = "exclamationmark.triangle.fill";
    public const string WindowsGlyph = "\uE7BA";
    public const string BackgroundHex = "#14FF453A";
    public const string BorderHex = "#33FF453A";
    public const string IconForegroundHex = "#FF453A";
    public const string TitleForegroundHex = "#F2F4F7";
    public const string DetailForegroundHex = "#A7B0BF";
    public const string RetryLabel = "Retry";
    public const string UseCachedLabel = "Use Cached Transcript";
    public const double Padding = 10;
    public const double CornerRadius = 8;
    public const double BorderThickness = 0;
    public const double ContentSpacing = 8;
    public const double HeaderColumnSpacing = 8;
    public const double TextStackSpacing = 3;
    public const double ActionSpacing = 8;
    public const double IconTopMargin = 1;
    public const double IconFontSize = 14;
    public const double TitleFontSize = 12;
    public const double DetailFontSize = 12;
    public const double ButtonHorizontalPadding = 10;
    public const double ButtonVerticalPadding = 5;
    public const double ButtonFontSize = 12;
    public const int DetailMaxLines = 4;

    public static TranscriptErrorPresentationSnapshot Resolve()
    {
        return new TranscriptErrorPresentationSnapshot(
            Title,
            MacSymbolName,
            WindowsGlyph,
            BackgroundHex,
            BorderHex,
            IconForegroundHex,
            TitleForegroundHex,
            DetailForegroundHex,
            RetryLabel,
            UseCachedLabel,
            Padding,
            CornerRadius,
            BorderThickness,
            ContentSpacing,
            HeaderColumnSpacing,
            TextStackSpacing,
            ActionSpacing,
            IconTopMargin,
            IconFontSize,
            TitleFontSize,
            DetailFontSize,
            ButtonHorizontalPadding,
            ButtonVerticalPadding,
            ButtonFontSize,
            DetailMaxLines);
    }
}
