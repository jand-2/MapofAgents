namespace MapofAgents.Core;

public readonly record struct ThreadInboxSearchFieldLayoutMetrics(
    double FontSize,
    double Height,
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double BorderThickness,
    string BackgroundHex,
    string PointerOverBackgroundHex,
    string BorderHex,
    string FocusedBorderHex,
    string ForegroundHex,
    string PlaceholderForegroundHex);

public static class ThreadInboxSearchFieldLayout
{
    public const double CaptionFontSize = 12;
    public const double FieldHeight = 28;
    public const double HorizontalPadding = 8;
    public const double VerticalPadding = 3;
    public const double CornerRadius = 6;
    public const double BorderThickness = 1;
    public const string BackgroundHex = "#142A2C30";
    public const string PointerOverBackgroundHex = "#1F2A2C30";
    public const string BorderHex = "#24FFFFFF";
    public const string FocusedBorderHex = "#660A84FF";
    public const string ForegroundHex = "#F2F4F7";
    public const string PlaceholderForegroundHex = "#8F9BAA";

    public static ThreadInboxSearchFieldLayoutMetrics Measure()
    {
        return new ThreadInboxSearchFieldLayoutMetrics(
            CaptionFontSize,
            FieldHeight,
            HorizontalPadding,
            VerticalPadding,
            CornerRadius,
            BorderThickness,
            BackgroundHex,
            PointerOverBackgroundHex,
            BorderHex,
            FocusedBorderHex,
            ForegroundHex,
            PlaceholderForegroundHex);
    }
}
