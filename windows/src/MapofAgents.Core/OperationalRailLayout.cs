namespace MapofAgents.Core;

public readonly record struct OperationalRailLayoutMetrics(
    double Width,
    double ContentWidth,
    double ContentInset,
    double TopInset,
    double RightInset,
    double BottomInset,
    double MaxHeight);

public static class OperationalRailLayout
{
    public const double Width = 334;
    public const double ContentWidth = 320;
    public const double ContentInset = 14;
    public const double TopInset = 58;
    public const double EdgeInset = 14;
    public const double InterRailGap = 10;
    public const double MinimumMaxHeight = 320;

    public static OperationalRailLayoutMetrics Measure(
        double rootHeight,
        bool reserveThreadInboxDock)
    {
        var reservedBottom = EdgeInset;
        if (reserveThreadInboxDock)
        {
            reservedBottom += ThreadInboxDockLayout.MinimumMaxHeight + InterRailGap;
        }

        var maxHeight = Math.Max(MinimumMaxHeight, rootHeight - TopInset - reservedBottom);

        return new OperationalRailLayoutMetrics(
            Width,
            ContentWidth,
            ContentInset,
            TopInset,
            EdgeInset,
            reservedBottom,
            maxHeight);
    }

    public static OperationalRailLayoutMetrics MeasureForBottomInboxOverlay(double rootHeight)
    {
        return Measure(rootHeight, reserveThreadInboxDock: false);
    }
}
