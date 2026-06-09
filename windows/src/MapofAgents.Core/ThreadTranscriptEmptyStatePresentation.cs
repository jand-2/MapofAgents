namespace MapofAgents.Core;

public readonly record struct ThreadTranscriptEmptyStatePresentationSnapshot(
    string Title,
    string Detail,
    string MacSymbolName,
    string WindowsGlyph,
    string BackgroundHex,
    string BorderHex,
    string TitleForegroundHex,
    string DetailForegroundHex,
    double Width,
    double MinHeight,
    double IconFontSize,
    double TitleFontSize,
    double DetailFontSize);

public static class ThreadTranscriptEmptyStatePresentation
{
    public const string Title = "No loaded turns";
    public const string Detail = "Send the first message or refresh after the thread starts responding.";
    public const string MacSymbolName = "text.bubble";
    public const string WindowsGlyph = "\uE8F2";
    public const string BackgroundHex = "#12697586";
    public const string BorderHex = "#24697586";
    public const string TitleForegroundHex = "#D7DCE5";
    public const string DetailForegroundHex = "#A7B0BF";
    public const double Width = 310;
    public const double MinHeight = 220;
    public const double IconFontSize = 24;
    public const double TitleFontSize = 13;
    public const double DetailFontSize = 13;

    public static ThreadTranscriptEmptyStatePresentationSnapshot Resolve()
    {
        return new ThreadTranscriptEmptyStatePresentationSnapshot(
            Title,
            Detail,
            MacSymbolName,
            WindowsGlyph,
            BackgroundHex,
            BorderHex,
            TitleForegroundHex,
            DetailForegroundHex,
            Width,
            MinHeight,
            IconFontSize,
            TitleFontSize,
            DetailFontSize);
    }
}
