namespace MapofAgents.Core;

public readonly record struct MentionSuggestionPanelPresentationSnapshot(
    double PanelPadding,
    double CornerRadius,
    double RowSpacing,
    double RowHorizontalPadding,
    double RowVerticalPadding,
    double IconWidth,
    double IconFontSize,
    double TitleFontSize,
    double SubtitleFontSize,
    double ContentSpacing,
    double ShadowTranslationZ,
    string TitleForegroundHex,
    string SubtitleForegroundHex);

public static class MentionSuggestionPanelPresentation
{
    public const double PanelPadding = 4;
    public const double CornerRadius = 8;
    public const double RowSpacing = 2;
    public const double RowHorizontalPadding = 8;
    public const double RowVerticalPadding = 6;
    public const double IconWidth = 18;
    public const double IconFontSize = 13;
    public const double TitleFontSize = 12;
    public const double SubtitleFontSize = 10;
    public const double ContentSpacing = 8;
    public const double ShadowTranslationZ = 18;
    public const string TitleForegroundHex = "#F2F4F7";
    public const string SubtitleForegroundHex = "#A7B0BF";
    public const string PluginForegroundHex = "#0A84FF";
    public const string FileForegroundHex = "#A7B0BF";
    public const string SkillForegroundHex = "#BF5AF2";
    public const string FolderForegroundHex = "#FFD60A";
    public const string ThreadForegroundHex = "#30D158";

    public static MentionSuggestionPanelPresentationSnapshot Resolve()
    {
        return new MentionSuggestionPanelPresentationSnapshot(
            PanelPadding,
            CornerRadius,
            RowSpacing,
            RowHorizontalPadding,
            RowVerticalPadding,
            IconWidth,
            IconFontSize,
            TitleFontSize,
            SubtitleFontSize,
            ContentSpacing,
            ShadowTranslationZ,
            TitleForegroundHex,
            SubtitleForegroundHex);
    }

    public static string ForegroundHexForKind(string? kind)
    {
        return kind?.Trim().ToLowerInvariant() switch
        {
            "plugin" => PluginForegroundHex,
            "file" => FileForegroundHex,
            "skill" => SkillForegroundHex,
            "folder" => FolderForegroundHex,
            _ => ThreadForegroundHex
        };
    }
}
