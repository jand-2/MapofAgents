namespace MapofAgents.Core;

public readonly record struct ThreadInboxWarningPresentationSnapshot(
    string Text,
    bool IsVisible,
    string MacSymbolName,
    string Glyph,
    string ForegroundHex,
    double FontSize,
    double IconFontSize,
    double IconWidth,
    int MaxLines);

public static class ThreadInboxWarningPresentation
{
    public const string Prefix = "Some inbox hosts may be stale:";
    public const string MacSymbolName = "exclamationmark.triangle.fill";
    public const string Glyph = "\uE7BA";
    public const string ForegroundHex = ThreadInboxPresentation.OrangeHex;
    public const double FontSize = 11;
    public const double IconFontSize = 11;
    public const double IconWidth = 14;
    public const int MaxLines = 2;

    public static ThreadInboxWarningPresentationSnapshot Resolve(string? errorMessage)
    {
        var trimmed = errorMessage?.Trim() ?? string.Empty;
        return new ThreadInboxWarningPresentationSnapshot(
            string.IsNullOrWhiteSpace(trimmed) ? string.Empty : $"{Prefix} {trimmed}",
            !string.IsNullOrWhiteSpace(trimmed),
            MacSymbolName,
            Glyph,
            ForegroundHex,
            FontSize,
            IconFontSize,
            IconWidth,
            MaxLines);
    }
}
