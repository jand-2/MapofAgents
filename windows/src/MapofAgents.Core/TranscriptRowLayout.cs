namespace MapofAgents.Core;

public readonly record struct TranscriptRowLayoutMetrics(
    double Padding,
    double CornerRadius,
    double ContentSpacing);

public static class TranscriptRowLayout
{
    public const double Padding = 10;
    public const double CornerRadius = 8;
    public const double ContentSpacing = 4;

    public static TranscriptRowLayoutMetrics Measure()
    {
        return new TranscriptRowLayoutMetrics(
            Padding,
            CornerRadius,
            ContentSpacing);
    }
}
