namespace MapofAgents.Core;

public readonly record struct ThreadInboxEmptyStateLayoutMetrics(
    double FontSize,
    double VerticalPadding);

public static class ThreadInboxEmptyStateLayout
{
    public const double CaptionFontSize = 12;
    public const double VerticalPadding = 8;

    public static ThreadInboxEmptyStateLayoutMetrics Measure()
    {
        return new ThreadInboxEmptyStateLayoutMetrics(CaptionFontSize, VerticalPadding);
    }
}
