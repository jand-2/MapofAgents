namespace MapofAgents.Core;

public readonly record struct ThreadComposerFooterPresentationSnapshot(
    double OuterPadding,
    double SectionSpacing,
    double MetadataItemSpacing,
    double MetadataChipSpacing,
    double MetadataFontSize,
    string MetadataForegroundHex,
    double InputActionSpacing,
    double MentionComposerSpacing,
    double ReplyInputStackSpacing,
    double ReplyActionStackSpacing);

public static class ThreadComposerFooterPresentation
{
    public const double OuterPadding = 14;
    public const double SectionSpacing = 10;
    public const double MetadataItemSpacing = 8;
    public const double MetadataChipSpacing = 5;
    public const double MetadataFontSize = 12;
    public const string MetadataForegroundHex = "#A7B0BF";
    public const double InputActionSpacing = 10;
    public const double MentionComposerSpacing = 6;
    public const double ReplyInputStackSpacing = 8;
    public const double ReplyActionStackSpacing = 8;

    public static ThreadComposerFooterPresentationSnapshot Resolve()
    {
        return new ThreadComposerFooterPresentationSnapshot(
            OuterPadding,
            SectionSpacing,
            MetadataItemSpacing,
            MetadataChipSpacing,
            MetadataFontSize,
            MetadataForegroundHex,
            InputActionSpacing,
            MentionComposerSpacing,
            ReplyInputStackSpacing,
            ReplyActionStackSpacing);
    }
}
