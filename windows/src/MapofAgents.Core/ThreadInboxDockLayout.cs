namespace MapofAgents.Core;

public readonly record struct ThreadInboxDockLayoutMetrics(
    double Width,
    double RightInset,
    double BottomInset,
    double MaxHeight,
    double Padding,
    double CornerRadius,
    double BorderThickness,
    double ShadowTranslationZ,
    int ZIndex);

public static class ThreadInboxDockLayout
{
    public const double Width = 320;
    public const double EdgeInset = 14;
    public const double TopClearance = 112;
    public const double MinimumMaxHeight = 220;
    public const double Padding = 12;
    public const double CornerRadius = 8;
    public const double BorderThickness = 1;
    public const double ShadowTranslationZ = 10;
    public const int OverlayZIndex = 20;

    public static ThreadInboxDockLayoutMetrics Measure(double rootHeight)
    {
        var maxHeight = Math.Max(MinimumMaxHeight, rootHeight - TopClearance);

        return new ThreadInboxDockLayoutMetrics(
            Width,
            EdgeInset,
            EdgeInset,
            maxHeight,
            Padding,
            CornerRadius,
            BorderThickness,
            ShadowTranslationZ,
            OverlayZIndex);
    }
}
