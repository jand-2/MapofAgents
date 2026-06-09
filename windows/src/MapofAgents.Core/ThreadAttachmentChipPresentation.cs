namespace MapofAgents.Core;

public readonly record struct ThreadAttachmentChipPresentationSnapshot(
    string KindGlyph,
    string KindForegroundHex,
    string ChipBackgroundHex,
    string ChipBorderHex,
    string NameForegroundHex,
    string DetailForegroundHex,
    string RemoveForegroundHex,
    double HorizontalPadding,
    double VerticalPadding,
    double ContentSpacing,
    double NameFontSize,
    double DetailFontSize,
    double IconFontSize,
    double RemoveIconFontSize);

public static class ThreadAttachmentChipPresentation
{
    public const string KindImage = "image";
    public const string KindDiff = "diff";
    public const string KindFile = "file";
    public const string ImageGlyph = "\uEB9F";
    public const string DiffGlyph = "\uE8AB";
    public const string FileGlyph = "\uE7C3";
    public const string ImageForegroundHex = "#0A84FF";
    public const string SecondaryForegroundHex = "#A7B0BF";
    public const string ChipBackgroundHex = "#1AFFFFFF";
    public const string ChipBorderHex = "#24FFFFFF";
    public const string NameForegroundHex = "#F2F4F7";
    public const string DetailForegroundHex = "#A7B0BF";
    public const string RemoveForegroundHex = "#8F9BAA";
    public const double HorizontalPadding = 9;
    public const double VerticalPadding = 7;
    public const double ContentSpacing = 6;
    public const double NameFontSize = 12;
    public const double DetailFontSize = 10;
    public const double IconFontSize = 12;
    public const double RemoveIconFontSize = 10;

    public static ThreadAttachmentChipPresentationSnapshot Resolve(string? kind)
    {
        var normalized = string.IsNullOrWhiteSpace(kind) ? KindFile : kind.Trim();
        var isImage = string.Equals(normalized, KindImage, StringComparison.OrdinalIgnoreCase);

        return new ThreadAttachmentChipPresentationSnapshot(
            GlyphFor(normalized),
            isImage ? ImageForegroundHex : SecondaryForegroundHex,
            ChipBackgroundHex,
            ChipBorderHex,
            NameForegroundHex,
            DetailForegroundHex,
            RemoveForegroundHex,
            HorizontalPadding,
            VerticalPadding,
            ContentSpacing,
            NameFontSize,
            DetailFontSize,
            IconFontSize,
            RemoveIconFontSize);
    }

    public static string GlyphFor(string? kind)
    {
        return kind?.Trim().ToLowerInvariant() switch
        {
            KindImage => ImageGlyph,
            KindDiff => DiffGlyph,
            _ => FileGlyph
        };
    }
}
