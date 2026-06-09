namespace MapofAgents.Core;

public readonly record struct ThreadStatusPresentationSnapshot(
    string Text,
    string Glyph,
    string IconKind,
    string MacSymbolName,
    string ForegroundHex,
    string BackgroundHex,
    string BorderHex,
    double BorderThickness,
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double MinWidth,
    double IconFontSize,
    double IconWidth,
    double IconHeight,
    double IconStrokeThickness,
    double TextFontSize);

public static class ThreadStatusPresentation
{
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";
    public const string BorderlessHex = "#00FFFFFF";
    public const string CircleIcon = "circle";
    public const string CircleFillIcon = "circleFill";
    public const string ArrowTriangleCirclePathIcon = "arrowTriangle2CirclePath";
    public const string ExclamationBubbleIcon = "exclamationBubble";
    public const string XmarkOctagonIcon = "xmarkOctagon";
    public const string CheckmarkCircleIcon = "checkmarkCircle";
    public const string CircleMacSymbolName = "circle";
    public const string CircleFillMacSymbolName = "circle.fill";
    public const string ArrowTriangleCirclePathMacSymbolName = "arrow.triangle.2.circlepath";
    public const string ExclamationBubbleMacSymbolName = "exclamationmark.bubble";
    public const string XmarkOctagonMacSymbolName = "xmark.octagon";
    public const string CheckmarkCircleMacSymbolName = "checkmark.circle";
    public const double PillBorderThickness = 0;
    public const double PillHorizontalPadding = 8;
    public const double PillVerticalPadding = 4;
    public const double PillCornerRadius = 10;
    public const double PillMinWidth = 0;
    public const double PillIconFontSize = 11;
    public const double PillIconWidth = 11;
    public const double PillIconHeight = 11;
    public const double PillIconStrokeThickness = 1.25;
    public const double PillTextFontSize = 11;

    public static ThreadStatusPresentationSnapshot Resolve(
        string? runStatus,
        bool isUnread = false)
    {
        if (isUnread)
        {
            return Snapshot("unread", "\uEA3A", CircleFillIcon, BlueHex);
        }

        var normalized = Normalize(runStatus);
        return Snapshot(
            normalized switch
            {
                ThreadRunStatuses.NeedsInput => "needs input",
                ThreadRunStatuses.Complete => "complete",
                ThreadRunStatuses.Failed => "failed",
                ThreadRunStatuses.Running => "running",
                ThreadRunStatuses.Unknown => "unknown",
                _ => "idle"
            },
            normalized switch
            {
                ThreadRunStatuses.NeedsInput => "\uE7BA",
                ThreadRunStatuses.Complete => "\uE73E",
                ThreadRunStatuses.Failed => "\uE711",
                ThreadRunStatuses.Running => "\uE895",
                _ => "\uEA3A"
            },
            normalized switch
            {
                ThreadRunStatuses.NeedsInput => ExclamationBubbleIcon,
                ThreadRunStatuses.Complete => CheckmarkCircleIcon,
                ThreadRunStatuses.Failed => XmarkOctagonIcon,
                ThreadRunStatuses.Running => ArrowTriangleCirclePathIcon,
                _ => CircleIcon
            },
            normalized switch
            {
                ThreadRunStatuses.NeedsInput => OrangeHex,
                ThreadRunStatuses.Complete => GreenHex,
                ThreadRunStatuses.Failed => RedHex,
                ThreadRunStatuses.Running => BlueHex,
                _ => SecondaryHex
            });
    }

    private static string Normalize(string? runStatus)
    {
        return runStatus switch
        {
            ThreadRunStatuses.Running => ThreadRunStatuses.Running,
            ThreadRunStatuses.NeedsInput => ThreadRunStatuses.NeedsInput,
            ThreadRunStatuses.Failed => ThreadRunStatuses.Failed,
            ThreadRunStatuses.Complete => ThreadRunStatuses.Complete,
            ThreadRunStatuses.Unknown => ThreadRunStatuses.Unknown,
            _ => ThreadRunStatuses.Idle
        };
    }

    private static ThreadStatusPresentationSnapshot Snapshot(
        string text,
        string glyph,
        string iconKind,
        string foregroundHex)
    {
        return new ThreadStatusPresentationSnapshot(
            text,
            glyph,
            iconKind,
            MacSymbolName(iconKind),
            foregroundHex,
            AlphaHex(foregroundHex, 0.11),
            BorderlessHex,
            PillBorderThickness,
            PillHorizontalPadding,
            PillVerticalPadding,
            PillCornerRadius,
            PillMinWidth,
            PillIconFontSize,
            PillIconWidth,
            PillIconHeight,
            PillIconStrokeThickness,
            PillTextFontSize);
    }

    private static string MacSymbolName(string iconKind)
    {
        return iconKind switch
        {
            CircleFillIcon => CircleFillMacSymbolName,
            ArrowTriangleCirclePathIcon => ArrowTriangleCirclePathMacSymbolName,
            ExclamationBubbleIcon => ExclamationBubbleMacSymbolName,
            XmarkOctagonIcon => XmarkOctagonMacSymbolName,
            CheckmarkCircleIcon => CheckmarkCircleMacSymbolName,
            _ => CircleMacSymbolName
        };
    }

    private static string AlphaHex(string hex, double opacity)
    {
        var clean = hex.TrimStart('#');
        var alpha = Math.Clamp((int)Math.Round(opacity * 255), 0, 255);
        return $"#{alpha:X2}{clean}";
    }
}
