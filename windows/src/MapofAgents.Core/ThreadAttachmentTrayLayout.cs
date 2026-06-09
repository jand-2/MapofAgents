namespace MapofAgents.Core;

public readonly record struct ThreadAttachmentTrayLayoutMetrics(
    double ItemSpacing,
    double BottomPadding,
    bool UsesSingleHorizontalRow);

public static class ThreadAttachmentTrayLayout
{
    public const double ItemSpacing = 8;
    public const double BottomPadding = 0;
    public const bool UsesSingleHorizontalRow = true;

    public static ThreadAttachmentTrayLayoutMetrics Measure()
    {
        return new ThreadAttachmentTrayLayoutMetrics(
            ItemSpacing,
            BottomPadding,
            UsesSingleHorizontalRow);
    }
}
