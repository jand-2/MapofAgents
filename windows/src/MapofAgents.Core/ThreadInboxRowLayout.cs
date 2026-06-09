namespace MapofAgents.Core;

public readonly record struct ThreadInboxRowLayoutMetrics(
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double RowSpacing,
    double TopRowIconTextSpacing,
    double TopRowStatusMinSpacing,
    double StatusBadgeLeadingInset,
    double ActionRowSpacing,
    double ActivityTimestampFontSize,
    int ActivityTimestampMaxLines,
    string ActivityTimestampForegroundHex,
    double PendingBadgeHorizontalPadding,
    double PendingBadgeVerticalPadding,
    double PendingBadgeCornerRadius,
    double PendingBadgeFontSize,
    string PendingBadgeForegroundHex,
    string PendingBadgeBackgroundHex,
    double StatusBadgeHorizontalPadding,
    double StatusBadgeVerticalPadding,
    double StatusBadgeCornerRadius,
    double StatusBadgeFontSize);

public static class ThreadInboxRowLayout
{
    public const double HorizontalPadding = 8;
    public const double VerticalPadding = 7;
    public const double CornerRadius = 8;
    public const double RowSpacing = 7;
    public const double TopRowIconTextSpacing = 8;
    public const double TopRowStatusMinSpacing = 6;
    public const double StatusBadgeLeadingInset = TopRowStatusMinSpacing - TopRowIconTextSpacing;
    public const double ActionRowSpacing = 8;
    public const double ActivityTimestampFontSize = 11;
    public const int ActivityTimestampMaxLines = 1;
    public const string ActivityTimestampForegroundHex = ThreadLiveStatePresentation.TertiaryHex;
    public const double PendingBadgeHorizontalPadding = 5;
    public const double PendingBadgeVerticalPadding = 1;
    public const double PendingBadgeCornerRadius = 8;
    public const double PendingBadgeFontSize = 11;
    public const string PendingBadgeForegroundHex = ThreadInboxPresentation.OrangeHex;
    public const string PendingBadgeBackgroundHex = "#24FF9F0A";
    public const double StatusBadgeHorizontalPadding = 5;
    public const double StatusBadgeVerticalPadding = 2;
    public const double StatusBadgeCornerRadius = 9;
    public const double StatusBadgeFontSize = 11;

    public static ThreadInboxRowLayoutMetrics Measure()
    {
        return new ThreadInboxRowLayoutMetrics(
            HorizontalPadding,
            VerticalPadding,
            CornerRadius,
            RowSpacing,
            TopRowIconTextSpacing,
            TopRowStatusMinSpacing,
            StatusBadgeLeadingInset,
            ActionRowSpacing,
            ActivityTimestampFontSize,
            ActivityTimestampMaxLines,
            ActivityTimestampForegroundHex,
            PendingBadgeHorizontalPadding,
            PendingBadgeVerticalPadding,
            PendingBadgeCornerRadius,
            PendingBadgeFontSize,
            PendingBadgeForegroundHex,
            PendingBadgeBackgroundHex,
            StatusBadgeHorizontalPadding,
            StatusBadgeVerticalPadding,
            StatusBadgeCornerRadius,
            StatusBadgeFontSize);
    }
}
