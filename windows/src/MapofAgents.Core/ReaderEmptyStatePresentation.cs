namespace MapofAgents.Core;

public readonly record struct ReaderEmptyStatePresentationSnapshot(
    string Title,
    string Detail,
    string MacSymbolName,
    string WindowsGlyph,
    string IconStrokeHex,
    string TitleForegroundHex,
    string DetailForegroundHex,
    double Width,
    double DetailMaxWidth,
    double StackSpacing,
    double IconWidth,
    double IconHeight,
    double IconStrokeThickness,
    double TitleFontSize,
    double DetailFontSize);

public static class ReaderEmptyStatePresentation
{
    public const string Title = "No Chats Selected";
    public const string Detail = "Use the thread picker above to open chats from the active workflow.";
    public const string MacSymbolName = "bubble.left.and.bubble.right";
    public const string WindowsGlyph = "\uE8F2";
    public const string IconStrokeHex = "#8F9BAA";
    public const string TitleForegroundHex = "#F2F4F7";
    public const string DetailForegroundHex = "#A7B0BF";
    public const double Width = 460;
    public const double DetailMaxWidth = 360;
    public const double StackSpacing = 10;
    public const double IconWidth = 48;
    public const double IconHeight = 40;
    public const double IconStrokeThickness = 2;
    public const double TitleFontSize = 20;
    public const double DetailFontSize = 12;

    public static ReaderEmptyStatePresentationSnapshot Resolve()
    {
        return new ReaderEmptyStatePresentationSnapshot(
            Title,
            Detail,
            MacSymbolName,
            WindowsGlyph,
            IconStrokeHex,
            TitleForegroundHex,
            DetailForegroundHex,
            Width,
            DetailMaxWidth,
            StackSpacing,
            IconWidth,
            IconHeight,
            IconStrokeThickness,
            TitleFontSize,
            DetailFontSize);
    }
}
