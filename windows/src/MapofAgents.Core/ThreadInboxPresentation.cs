namespace MapofAgents.Core;

public readonly record struct ThreadInboxPresentationSnapshot(
    string StatusText,
    string LeadingGlyph,
    string LeadingIconKind,
    string LeadingMacSymbolName,
    bool LeadingUsesThreadPairIcon,
    string LeadingHex,
    string StatusHex,
    string StatusBackgroundHex,
    string LiveStateIconKind,
    string LiveStateGlyph,
    string LiveStateText,
    string LiveStateTitle,
    string LiveStateDetail,
    string LiveStateHex);

public static class ThreadInboxPresentation
{
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string PurpleHex = "#BF5AF2";
    public const string SecondaryHex = "#A7B0BF";
    public const string TertiaryHex = "#8F9BAA";
    public const string LeadingThreadPairIcon = "threadPair";
    public const string LeadingSubagentGlyphIcon = "subagentGlyph";
    public const string LeadingRunningIcon = "arrowTriangle2CirclePath";
    public const string LeadingNeedsInputIcon = "exclamationmarkBubble";
    public const string LeadingFailedIcon = "xmarkOctagon";
    public const string LeadingThreadPairMacSymbolName = "bubble.left.and.bubble.right";
    public const string LeadingSubagentMacSymbolName = "person.2";
    public const string LeadingRunningMacSymbolName = "arrow.triangle.2.circlepath";
    public const string LeadingNeedsInputMacSymbolName = "exclamationmark.bubble";
    public const string LeadingFailedMacSymbolName = "xmark.octagon";
    public const double LeadingStatusIconWidth = 18;
    public const double LeadingStatusIconHeight = 18;
    public const double LeadingStatusIconStrokeThickness = 1.25;

    public static ThreadInboxPresentationSnapshot Resolve(
        string? runStatus,
        bool isSubagent,
        int pendingRequestCount,
        string? liveDetail = null)
    {
        var normalized = NormalizeStatus(runStatus);
        var statusHex = StatusHex(normalized);
        var liveState = ThreadLiveStatePresentation.Resolve(
            normalized,
            pendingRequestCount,
            liveDetail);

        return new ThreadInboxPresentationSnapshot(
            StatusText(normalized),
            LeadingGlyph(normalized, isSubagent),
            LeadingIconKind(normalized, isSubagent),
            LeadingMacSymbolName(normalized, isSubagent),
            LeadingUsesThreadPairIcon(normalized, isSubagent),
            LeadingHex(normalized, isSubagent),
            statusHex,
            AlphaHex(statusHex, 0.12),
            liveState.IconKind,
            liveState.Glyph,
            liveState.Text,
            liveState.Title,
            liveState.Detail,
            liveState.ForegroundHex);
    }

    private static string NormalizeStatus(string? status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => ThreadRunStatuses.Running,
            ThreadRunStatuses.NeedsInput => ThreadRunStatuses.NeedsInput,
            ThreadRunStatuses.Failed => ThreadRunStatuses.Failed,
            ThreadRunStatuses.Complete => ThreadRunStatuses.Complete,
            ThreadRunStatuses.Unknown => ThreadRunStatuses.Unknown,
            _ => ThreadRunStatuses.Idle
        };
    }

    private static string StatusText(string status)
    {
        return status switch
        {
            ThreadRunStatuses.NeedsInput => "needs",
            ThreadRunStatuses.Complete => "finished",
            ThreadRunStatuses.Failed => "failed",
            ThreadRunStatuses.Running => "running",
            ThreadRunStatuses.Unknown => "unknown",
            _ => "idle"
        };
    }

    private static string LeadingGlyph(string status, bool isSubagent)
    {
        return status switch
        {
            ThreadRunStatuses.Running => "\uE895",
            ThreadRunStatuses.NeedsInput => "\uE7BA",
            ThreadRunStatuses.Failed => "\uE711",
            _ => isSubagent ? "\uE716" : "\uE8F2"
        };
    }

    private static bool LeadingUsesThreadPairIcon(string status, bool isSubagent)
    {
        return !isSubagent &&
            status is not ThreadRunStatuses.Running
                and not ThreadRunStatuses.NeedsInput
                and not ThreadRunStatuses.Failed;
    }

    private static string LeadingIconKind(string status, bool isSubagent)
    {
        return status switch
        {
            ThreadRunStatuses.Running => LeadingRunningIcon,
            ThreadRunStatuses.NeedsInput => LeadingNeedsInputIcon,
            ThreadRunStatuses.Failed => LeadingFailedIcon,
            _ => isSubagent ? LeadingSubagentGlyphIcon : LeadingThreadPairIcon
        };
    }

    private static string LeadingMacSymbolName(string status, bool isSubagent)
    {
        return status switch
        {
            ThreadRunStatuses.Running => LeadingRunningMacSymbolName,
            ThreadRunStatuses.NeedsInput => LeadingNeedsInputMacSymbolName,
            ThreadRunStatuses.Failed => LeadingFailedMacSymbolName,
            _ => isSubagent ? LeadingSubagentMacSymbolName : LeadingThreadPairMacSymbolName
        };
    }

    private static string LeadingHex(string status, bool isSubagent)
    {
        return status switch
        {
            ThreadRunStatuses.Running => BlueHex,
            ThreadRunStatuses.NeedsInput => OrangeHex,
            ThreadRunStatuses.Failed => RedHex,
            ThreadRunStatuses.Complete => GreenHex,
            _ => isSubagent ? PurpleHex : SecondaryHex
        };
    }

    private static string StatusHex(string status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => BlueHex,
            ThreadRunStatuses.NeedsInput => OrangeHex,
            ThreadRunStatuses.Failed => RedHex,
            ThreadRunStatuses.Complete => GreenHex,
            _ => SecondaryHex
        };
    }

    private static string AlphaHex(string hex, double opacity)
    {
        var clean = hex.TrimStart('#');
        var alpha = Math.Clamp((int)Math.Round(opacity * 255), 0, 255);
        return $"#{alpha:X2}{clean}";
    }
}
