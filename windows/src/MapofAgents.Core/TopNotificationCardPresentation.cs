namespace MapofAgents.Core;

public readonly record struct TopNotificationCardPresentationSnapshot(
    double StackSpacing,
    double DismissAllHorizontalPadding,
    double DismissAllVerticalPadding,
    double DismissAllCornerRadius,
    double DismissAllFontSize,
    double Width,
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double BorderThickness,
    double ColumnSpacing,
    double IconFrameSize,
    double IconTopMargin,
    double FontGlyphSize,
    double FilledIconSize,
    double ContentSpacing,
    double TitleFontSize,
    double MessageFontSize,
    int MessageMaxLines,
    double TimelineFontSize,
    int TimelineMaxLines,
    double DismissButtonSize,
    double DismissIconFontSize,
    double ShadowTranslationZ,
    double BottomGap);

public static class TopNotificationCardPresentation
{
    public const double StackSpacing = 8;
    public const double DismissAllHorizontalPadding = 10;
    public const double DismissAllVerticalPadding = 5;
    public const double DismissAllCornerRadius = 14;
    public const double DismissAllFontSize = 12;
    public const double Width = 360;
    public const double HorizontalPadding = 12;
    public const double VerticalPadding = 10;
    public const double CornerRadius = 8;
    public const double BorderThickness = 1;
    public const double ColumnSpacing = 10;
    public const double IconFrameSize = 18;
    public const double IconTopMargin = 1;
    public const double FontGlyphSize = 14;
    public const double FilledIconSize = 17;
    public const double ContentSpacing = 5;
    public const double TitleFontSize = 12;
    public const double MessageFontSize = 12;
    public const int MessageMaxLines = 3;
    public const double TimelineFontSize = 10;
    public const int TimelineMaxLines = 2;
    public const double DismissButtonSize = 18;
    public const double DismissIconFontSize = 11;
    public const double ShadowTranslationZ = 18;
    public const double BottomGap = 8;

    public static TopNotificationCardPresentationSnapshot Resolve()
    {
        return new TopNotificationCardPresentationSnapshot(
            StackSpacing,
            DismissAllHorizontalPadding,
            DismissAllVerticalPadding,
            DismissAllCornerRadius,
            DismissAllFontSize,
            Width,
            HorizontalPadding,
            VerticalPadding,
            CornerRadius,
            BorderThickness,
            ColumnSpacing,
            IconFrameSize,
            IconTopMargin,
            FontGlyphSize,
            FilledIconSize,
            ContentSpacing,
            TitleFontSize,
            MessageFontSize,
            MessageMaxLines,
            TimelineFontSize,
            TimelineMaxLines,
            DismissButtonSize,
            DismissIconFontSize,
            ShadowTranslationZ,
            BottomGap);
    }
}
