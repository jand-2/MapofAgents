namespace MapofAgents.Core;

public readonly record struct ThreadLiveStatePresentationSnapshot(
    string IconKind,
    string MacSymbolName,
    string Glyph,
    string Text,
    string ForegroundHex,
    string Title,
    string Detail,
    double IconWidth,
    double IconHeight,
    double StrokeThickness);

public static class ThreadLiveStatePresentation
{
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";
    public const string TertiaryHex = "#8F9BAA";

    public const string ClockIcon = "clock";
    public const string ArrowTriangleCirclePathIcon = "arrowTriangle2CirclePath";
    public const string HandRaisedIcon = "handRaised";
    public const string CheckmarkCircleIcon = "checkmarkCircle";
    public const string XmarkOctagonIcon = "xmarkOctagon";

    public const string ClockMacSymbolName = "clock";
    public const string ArrowTriangleCirclePathMacSymbolName = "arrow.triangle.2.circlepath";
    public const string HandRaisedMacSymbolName = "hand.raised";
    public const string CheckmarkCircleMacSymbolName = "checkmark.circle";
    public const string XmarkOctagonMacSymbolName = "xmark.octagon";

    public const double IconWidth = 14;
    public const double IconHeight = 12;
    public const double StrokeThickness = 1.1;

    public static ThreadLiveStatePresentationSnapshot Resolve(
        string? runStatus,
        int pendingRequestCount = 0,
        string? detail = null)
    {
        var normalized = NormalizeStatus(runStatus);
        var title = Title(normalized, pendingRequestCount);
        var normalizedDetail = Detail(title, detail);
        var iconKind = IconKind(normalized, pendingRequestCount);
        return new ThreadLiveStatePresentationSnapshot(
            iconKind,
            MacSymbolName(iconKind),
            Glyph(normalized, pendingRequestCount),
            Text(title, normalizedDetail),
            ForegroundHex(normalized, pendingRequestCount),
            title,
            normalizedDetail,
            IconWidth,
            IconHeight,
            StrokeThickness);
    }

    private static string NormalizeStatus(string? status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => ThreadRunStatuses.Running,
            ThreadRunStatuses.NeedsInput => ThreadRunStatuses.NeedsInput,
            ThreadRunStatuses.Failed => ThreadRunStatuses.Failed,
            ThreadRunStatuses.Complete => ThreadRunStatuses.Complete,
            _ => ThreadRunStatuses.Idle
        };
    }

    private static string Title(string status, int pendingRequestCount)
    {
        return status switch
        {
            _ when pendingRequestCount > 0 => "Waiting for approval",
            ThreadRunStatuses.NeedsInput => "Waiting for input",
            ThreadRunStatuses.Running => "Working",
            ThreadRunStatuses.Complete => "Finished",
            ThreadRunStatuses.Failed => "Failed",
            _ => "Idle"
        };
    }

    private static string Detail(string title, string? detail)
    {
        var trimmed = string.IsNullOrWhiteSpace(detail) ? "" : detail.Trim();
        return string.Equals(trimmed, title, StringComparison.OrdinalIgnoreCase)
            ? ""
            : trimmed;
    }

    private static string Text(string title, string detail)
    {
        return string.IsNullOrWhiteSpace(detail)
            ? title
            : $"{title} \u00B7 {detail}";
    }

    private static string Glyph(string status, int pendingRequestCount)
    {
        return status switch
        {
            _ when pendingRequestCount > 0 => "\uE7BA",
            ThreadRunStatuses.NeedsInput => "\uE7BA",
            ThreadRunStatuses.Running => "\uE895",
            ThreadRunStatuses.Complete => "\uE73E",
            ThreadRunStatuses.Failed => "\uE711",
            _ => "\uE823"
        };
    }

    private static string IconKind(string status, int pendingRequestCount)
    {
        return status switch
        {
            _ when pendingRequestCount > 0 => HandRaisedIcon,
            ThreadRunStatuses.NeedsInput => HandRaisedIcon,
            ThreadRunStatuses.Running => ArrowTriangleCirclePathIcon,
            ThreadRunStatuses.Complete => CheckmarkCircleIcon,
            ThreadRunStatuses.Failed => XmarkOctagonIcon,
            _ => ClockIcon
        };
    }

    private static string MacSymbolName(string iconKind)
    {
        return iconKind switch
        {
            ArrowTriangleCirclePathIcon => ArrowTriangleCirclePathMacSymbolName,
            HandRaisedIcon => HandRaisedMacSymbolName,
            CheckmarkCircleIcon => CheckmarkCircleMacSymbolName,
            XmarkOctagonIcon => XmarkOctagonMacSymbolName,
            _ => ClockMacSymbolName
        };
    }

    private static string ForegroundHex(string status, int pendingRequestCount)
    {
        return status switch
        {
            _ when pendingRequestCount > 0 => OrangeHex,
            ThreadRunStatuses.NeedsInput => OrangeHex,
            ThreadRunStatuses.Running => BlueHex,
            ThreadRunStatuses.Complete => GreenHex,
            ThreadRunStatuses.Failed => RedHex,
            _ => SecondaryHex
        };
    }
}
