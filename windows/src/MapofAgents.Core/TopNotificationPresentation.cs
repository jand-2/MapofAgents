namespace MapofAgents.Core;

public readonly record struct TopNotificationPresentationSnapshot(
    string Title,
    string Action,
    string Glyph,
    string IconKind,
    string MacSymbolName,
    string ForegroundHex,
    string MessageHex,
    string BorderHex);

public static class TopNotificationPresentation
{
    public const string GeneralKind = "general";
    public const string CompletedKind = "completed";
    public const string NeedsInputKind = "needsInput";
    public const string FailedKind = "failed";

    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";
    public const string DefaultBorderHex = "#24FFFFFF";
    public const string TintBorderAlphaHex = "38";
    public const string WarningTriangleGlyph = "\uE7BA";
    public const string FontGlyphIcon = "fontGlyph";
    public const string CheckmarkCircleFillIcon = "checkmarkCircleFill";
    public const string ExclamationBubbleFillIcon = "exclamationBubbleFill";
    public const string XmarkOctagonFillIcon = "xmarkOctagonFill";
    public const string CheckmarkCircleFillMacSymbolName = "checkmark.circle.fill";
    public const string ExclamationBubbleFillMacSymbolName = "exclamationmark.bubble.fill";
    public const string XmarkOctagonFillMacSymbolName = "xmark.octagon.fill";

    public static TopNotificationPresentationSnapshot Resolve(string message, string notificationKind)
    {
        var trimmed = string.IsNullOrWhiteSpace(message) ? "Activity updated." : message.Trim();
        var kind = NormalizeKind(notificationKind);
        var foreground = ForegroundHex(trimmed, kind);
        var iconKind = IconKind(trimmed, kind);

        return new TopNotificationPresentationSnapshot(
            Title(trimmed, kind),
            Action(trimmed, kind),
            Glyph(trimmed, kind),
            iconKind,
            MacSymbolName(iconKind),
            foreground,
            kind == FailedKind || IsFailure(trimmed) ? RedHex : SecondaryHex,
            BorderHex(foreground, kind, trimmed));
    }

    private static string NormalizeKind(string notificationKind)
    {
        return notificationKind switch
        {
            CompletedKind => CompletedKind,
            NeedsInputKind => NeedsInputKind,
            FailedKind => FailedKind,
            _ => GeneralKind
        };
    }

    private static string Title(string message, string kind)
    {
        return kind switch
        {
            CompletedKind => "Turn completed",
            NeedsInputKind => "Needs input",
            FailedKind => "Action failed",
            _ when IsFailure(message) => "Action failed",
            _ when IsConnectionUpdate(message) => "Connection updated",
            _ when Contains(message, "thread") => "Thread activity",
            _ when Contains(message, "workflow") => "Workflow activity",
            _ => "MapofAgents"
        };
    }

    private static string Action(string message, string kind)
    {
        return kind switch
        {
            CompletedKind => "Turn completed",
            NeedsInputKind => "Needs input",
            FailedKind => "Failed",
            _ when Contains(message, "created") && Contains(message, "thread") => "Thread created",
            _ when Contains(message, "started") || Contains(message, "connecting") => "Turn started",
            _ when IsConnectionUpdate(message) => "Connection updated",
            _ => "Activity"
        };
    }

    private static string Glyph(string message, string kind)
    {
        return kind switch
        {
            CompletedKind => "\uE73E",
            NeedsInputKind => WarningTriangleGlyph,
            FailedKind => WarningTriangleGlyph,
            _ when IsFailure(message) => WarningTriangleGlyph,
            _ when IsConnectionUpdate(message) => "\uE930",
            _ when Contains(message, "thread") => "\uE8F2",
            _ when Contains(message, "workflow") => "\uE8BD",
            _ => "\uE946"
        };
    }

    private static string IconKind(string message, string kind)
    {
        return kind switch
        {
            CompletedKind => CheckmarkCircleFillIcon,
            NeedsInputKind => ExclamationBubbleFillIcon,
            FailedKind => XmarkOctagonFillIcon,
            _ when IsFailure(message) => XmarkOctagonFillIcon,
            _ => FontGlyphIcon
        };
    }

    private static string MacSymbolName(string iconKind)
    {
        return iconKind switch
        {
            CheckmarkCircleFillIcon => CheckmarkCircleFillMacSymbolName,
            ExclamationBubbleFillIcon => ExclamationBubbleFillMacSymbolName,
            XmarkOctagonFillIcon => XmarkOctagonFillMacSymbolName,
            _ => "bell.badge"
        };
    }

    private static string ForegroundHex(string message, string kind)
    {
        return kind switch
        {
            CompletedKind => GreenHex,
            NeedsInputKind => OrangeHex,
            FailedKind => RedHex,
            _ when IsFailure(message) => RedHex,
            _ when IsConnectionUpdate(message) => GreenHex,
            _ when Contains(message, "thread") => BlueHex,
            _ when Contains(message, "workflow") => "#BF5AF2",
            _ => SecondaryHex
        };
    }

    private static string BorderHex(string foregroundHex, string kind, string message)
    {
        if (kind == GeneralKind &&
            !IsFailure(message) &&
            !IsConnectionUpdate(message) &&
            !Contains(message, "thread") &&
            !Contains(message, "workflow"))
        {
            return DefaultBorderHex;
        }

        return "#" + TintBorderAlphaHex + foregroundHex.TrimStart('#');
    }

    private static bool IsFailure(string message)
    {
        return Contains(message, "failed") ||
            Contains(message, "error") ||
            Contains(message, "invalid");
    }

    private static bool IsConnectionUpdate(string message)
    {
        return Contains(message, "connected") ||
            Contains(message, "disconnected");
    }

    private static bool Contains(string message, string value)
    {
        return message.Contains(value, StringComparison.OrdinalIgnoreCase);
    }
}
