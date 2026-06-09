namespace MapofAgents.Core;

public readonly record struct MentionComposerLayoutMetrics(
    double Height,
    double MinHeight,
    double MaxHeight,
    int VisibleLines,
    int EstimatedLines);

public static class MentionComposerLayout
{
    public const int DefaultMinLines = 2;
    public const int DefaultMaxLines = 5;
    public const int ThreadReplyMinLines = 3;
    public const int ThreadReplyMaxLines = 8;
    public const int NewThreadMinLines = 4;
    public const int NewThreadMaxLines = 9;
    public const double CharactersPerVisualLine = 54;
    public const double LineHeight = 19;
    public const double VerticalChrome = 22;

    public static MentionComposerLayoutMetrics Measure(
        string? text,
        int minLines = DefaultMinLines,
        int maxLines = DefaultMaxLines)
    {
        var normalizedMinLines = Math.Max(1, minLines);
        var normalizedMaxLines = Math.Max(normalizedMinLines, maxLines);
        var estimatedLines = EstimatedLineCount(text);
        var visibleLines = Math.Min(
            Math.Max(normalizedMinLines, estimatedLines),
            normalizedMaxLines);

        return new MentionComposerLayoutMetrics(
            HeightForLines(visibleLines),
            HeightForLines(normalizedMinLines),
            HeightForLines(normalizedMaxLines),
            visibleLines,
            estimatedLines);
    }

    private static int EstimatedLineCount(string? text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return 1;
        }

        return text
            .Split('\n')
            .Sum(line => Math.Max(1, (int)Math.Ceiling(CleanLineLength(line) / CharactersPerVisualLine)));
    }

    private static int CleanLineLength(string line)
    {
        return line.EndsWith('\r') ? line.Length - 1 : line.Length;
    }

    private static double HeightForLines(int lines)
    {
        return Math.Max(1, lines) * LineHeight + VerticalChrome;
    }
}
