namespace MapofAgents.Core;

public readonly record struct TranscriptToolRowPresentationSnapshot(
    string Title,
    string Body,
    string Summary,
    bool HasDetails,
    string ShowDetailsLabel,
    string HideDetailsLabel);

public static class TranscriptToolRowPresentation
{
    public const string DefaultTitle = "Tool";
    public const string NoDetailsSummary = "No details";
    public const string DetailsAvailableSummary = "Details available";
    public const string ShowDetailsLabel = "Show details";
    public const string HideDetailsLabel = "Hide details";

    public static TranscriptToolRowPresentationSnapshot Resolve(string? text)
    {
        var value = text ?? "";
        var lines = value.Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None);
        var title = lines
            .FirstOrDefault(line => !string.IsNullOrWhiteSpace(line))?
            .Trim();

        var body = lines.Length > 1
            ? string.Join("\n", lines.Skip(1)).Trim()
            : value.Trim();

        var summary = SummaryFor(body);
        return new TranscriptToolRowPresentationSnapshot(
            string.IsNullOrWhiteSpace(title) ? DefaultTitle : title!,
            body,
            summary,
            !string.IsNullOrWhiteSpace(body),
            ShowDetailsLabel,
            HideDetailsLabel);
    }

    private static string SummaryFor(string body)
    {
        if (string.IsNullOrWhiteSpace(body))
        {
            return NoDetailsSummary;
        }

        var compact = body
            .Split(new[] { "\r\n", "\n", "\r" }, StringSplitOptions.None)
            .FirstOrDefault()?
            .Trim() ?? "";
        return string.IsNullOrWhiteSpace(compact) ? DetailsAvailableSummary : compact;
    }
}
