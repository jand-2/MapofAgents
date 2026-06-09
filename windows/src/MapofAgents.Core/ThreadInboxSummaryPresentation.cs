namespace MapofAgents.Core;

public readonly record struct ThreadInboxSummarySnapshot(
    string ThreadSummaryText,
    bool ShowThreadSummary,
    string AttentionSummaryText,
    bool ShowAttentionSection,
    bool ShowEmptyState,
    double SummaryFontSize,
    string SummaryForegroundHex,
    string SummaryFontWeight,
    double AttentionRequestListMaxHeight,
    double ThreadListMaxHeight);

public static class ThreadInboxSummaryPresentation
{
    public const string NeedsYouMode = "needsYou";
    public const double SummaryFontSize = 11;
    public const string SummaryForegroundHex = ThreadInboxPresentation.TertiaryHex;
    public const string SummaryFontWeight = "Normal";
    public const double DefaultThreadListMaxHeight = 360;
    public const double AttentionRequestListMaxHeight = 360;
    public const double NeedsYouThreadListMaxHeight = 300;

    public static ThreadInboxSummarySnapshot Resolve(
        string? mode,
        int threadCount,
        int requestCount)
    {
        var needsYou = string.Equals(mode, NeedsYouMode, StringComparison.OrdinalIgnoreCase);
        return new ThreadInboxSummarySnapshot(
            ThreadSummaryText(threadCount, needsYou),
            threadCount > 0,
            Pluralize(requestCount, "request"),
            needsYou && requestCount > 0,
            threadCount == 0 && (!needsYou || requestCount == 0),
            SummaryFontSize,
            SummaryForegroundHex,
            SummaryFontWeight,
            AttentionRequestListMaxHeight,
            needsYou ? NeedsYouThreadListMaxHeight : DefaultThreadListMaxHeight);
    }

    private static string ThreadSummaryText(int count, bool needsYou)
    {
        var text = Pluralize(count, "thread");
        return needsYou ? $"{text} with attention" : text;
    }

    private static string Pluralize(int count, string singular)
    {
        return $"{count} {singular}{(count == 1 ? string.Empty : "s")}";
    }
}
