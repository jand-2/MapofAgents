namespace MapofAgents.Core;

public readonly record struct GraphNodeStatusPresentationSnapshot(
    string Label,
    string Glyph,
    string IconKind,
    string MacSymbolName,
    bool ShowsGlyph,
    string ForegroundHex,
    string BackgroundCss,
    string BorderCss);

public static class GraphNodeStatusPresentation
{
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";
    public const string CircleIcon = "circle";
    public const string CircleFillIcon = "circleFill";
    public const string ArrowTriangleCirclePathIcon = "arrowTriangle2CirclePath";
    public const string ExclamationBubbleIcon = "exclamationBubble";
    public const string XmarkOctagonIcon = "xmarkOctagon";
    public const string CheckmarkCircleIcon = "checkmarkCircle";
    public const string FolderIcon = "folder";
    public const string CircleMacSymbolName = "circle";
    public const string CircleFillMacSymbolName = "circle.fill";
    public const string ArrowTriangleCirclePathMacSymbolName = "arrow.triangle.2.circlepath";
    public const string ExclamationBubbleMacSymbolName = "exclamationmark.bubble";
    public const string XmarkOctagonMacSymbolName = "xmark.octagon";
    public const string CheckmarkCircleMacSymbolName = "checkmark.circle";
    public const string FolderMacSymbolName = "folder";

    public static GraphNodeStatusPresentationSnapshot Machine(string? hostStatus)
    {
        var normalized = hostStatus switch
        {
            HostStatuses.Connected => HostStatuses.Connected,
            HostStatuses.Connecting => HostStatuses.Connecting,
            HostStatuses.Unavailable => HostStatuses.Unavailable,
            _ => HostStatuses.Disconnected
        };

        var foreground = normalized == HostStatuses.Connected ? GreenHex : SecondaryHex;
        return Snapshot(
            normalized switch
            {
                HostStatuses.Connected => "connected",
                HostStatuses.Connecting => "connecting",
                HostStatuses.Unavailable => "runtime failed",
                _ => "offline"
            },
            normalized == HostStatuses.Connected ? "\uE73E" : "\uEA3A",
            normalized == HostStatuses.Connected ? CheckmarkCircleIcon : CircleIcon,
            showsGlyph: false,
            foreground);
    }

    public static GraphNodeStatusPresentationSnapshot Folder()
    {
        return Snapshot("folder", "\uE8B7", FolderIcon, showsGlyph: false, SecondaryHex);
    }

    public static GraphNodeStatusPresentationSnapshot Thread(string? runStatus, bool isUnread)
    {
        if (isUnread)
        {
            return Snapshot("unread", "\uEA3A", CircleFillIcon, showsGlyph: true, BlueHex);
        }

        var normalized = runStatus switch
        {
            ThreadRunStatuses.Running => ThreadRunStatuses.Running,
            ThreadRunStatuses.NeedsInput => ThreadRunStatuses.NeedsInput,
            ThreadRunStatuses.Failed => ThreadRunStatuses.Failed,
            ThreadRunStatuses.Complete => ThreadRunStatuses.Complete,
            ThreadRunStatuses.Idle => ThreadRunStatuses.Idle,
            _ => ThreadRunStatuses.Unknown
        };

        return Snapshot(
            normalized,
            normalized switch
            {
                ThreadRunStatuses.Running => "\uE895",
                ThreadRunStatuses.NeedsInput => "\uE7BA",
                ThreadRunStatuses.Failed => "\uE711",
                ThreadRunStatuses.Complete => "\uE73E",
                _ => "\uEA3A"
            },
            normalized switch
            {
                ThreadRunStatuses.Running => ArrowTriangleCirclePathIcon,
                ThreadRunStatuses.NeedsInput => ExclamationBubbleIcon,
                ThreadRunStatuses.Failed => XmarkOctagonIcon,
                ThreadRunStatuses.Complete => CheckmarkCircleIcon,
                _ => CircleIcon
            },
            showsGlyph: true,
            normalized switch
            {
                ThreadRunStatuses.Running => BlueHex,
                ThreadRunStatuses.NeedsInput => OrangeHex,
                ThreadRunStatuses.Failed => RedHex,
                ThreadRunStatuses.Complete => GreenHex,
                _ => SecondaryHex
            });
    }

    public static IReadOnlyDictionary<string, IReadOnlyDictionary<string, GraphNodeStatusPresentationSnapshot>> WebPresentationMap()
    {
        return new Dictionary<string, IReadOnlyDictionary<string, GraphNodeStatusPresentationSnapshot>>(StringComparer.Ordinal)
        {
            ["machine"] = new Dictionary<string, GraphNodeStatusPresentationSnapshot>(StringComparer.Ordinal)
            {
                [HostStatuses.Connected] = Machine(HostStatuses.Connected),
                [HostStatuses.Connecting] = Machine(HostStatuses.Connecting),
                [HostStatuses.Disconnected] = Machine(HostStatuses.Disconnected),
                [HostStatuses.Unavailable] = Machine(HostStatuses.Unavailable)
            },
            ["folder"] = new Dictionary<string, GraphNodeStatusPresentationSnapshot>(StringComparer.Ordinal)
            {
                ["folder"] = Folder()
            },
            ["thread"] = new Dictionary<string, GraphNodeStatusPresentationSnapshot>(StringComparer.Ordinal)
            {
                ["unread"] = Thread(ThreadRunStatuses.Unknown, isUnread: true),
                [ThreadRunStatuses.Running] = Thread(ThreadRunStatuses.Running, isUnread: false),
                [ThreadRunStatuses.NeedsInput] = Thread(ThreadRunStatuses.NeedsInput, isUnread: false),
                [ThreadRunStatuses.Failed] = Thread(ThreadRunStatuses.Failed, isUnread: false),
                [ThreadRunStatuses.Complete] = Thread(ThreadRunStatuses.Complete, isUnread: false),
                [ThreadRunStatuses.Idle] = Thread(ThreadRunStatuses.Idle, isUnread: false),
                [ThreadRunStatuses.Unknown] = Thread(ThreadRunStatuses.Unknown, isUnread: false)
            }
        };
    }

    private static GraphNodeStatusPresentationSnapshot Snapshot(
        string label,
        string glyph,
        string iconKind,
        bool showsGlyph,
        string foregroundHex)
    {
        return new GraphNodeStatusPresentationSnapshot(
            label,
            glyph,
            iconKind,
            MacSymbolName(iconKind),
            showsGlyph,
            foregroundHex,
            Rgba(foregroundHex, 0.10),
            Rgba(foregroundHex, 0.18));
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
            FolderIcon => FolderMacSymbolName,
            _ => CircleMacSymbolName
        };
    }

    private static string Rgba(string hex, double alpha)
    {
        var clean = hex.TrimStart('#');
        var red = Convert.ToInt32(clean[..2], 16);
        var green = Convert.ToInt32(clean[2..4], 16);
        var blue = Convert.ToInt32(clean[4..6], 16);
        return $"rgba({red}, {green}, {blue}, {alpha:0.00})";
    }
}
