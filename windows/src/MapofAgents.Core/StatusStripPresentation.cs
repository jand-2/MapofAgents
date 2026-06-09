namespace MapofAgents.Core;

public readonly record struct StatusStripStatusSnapshot(
    string Text,
    string Glyph,
    string IconKind,
    string ForegroundHex,
    string HelpText);

public static class StatusStripPresentation
{
    public const string LocalDisconnectedIcon = "circle";
    public const string LocalConnectedIcon = "checkmark.circle.fill";
    public const string LocalConnectingIcon = "arrow.triangle.2.circlepath";
    public const string WarningIcon = "exclamationmark.triangle.fill";
    public const string RemoteAntennaIcon = "antenna.radiowaves.left.and.right";
    public const string ConnectedHex = "#30D158";
    public const string ConnectingHex = "#0A84FF";
    public const string UnavailableHex = "#FF9F0A";
    public const string ErrorHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";

    public static StatusStripStatusSnapshot Local(
        string status,
        string message,
        string? helpText = null)
    {
        var normalized = NormalizeLocalStatus(status);
        var normalizedMessage = NormalizeMessage(message, DefaultLocalMessage(normalized));
        var normalizedHelp = NormalizeMessage(helpText, normalizedMessage);

        return new StatusStripStatusSnapshot(
            $"Local: {normalizedMessage}",
            LocalGlyph(normalized),
            LocalIconKind(normalized),
            LocalColor(normalized),
            normalizedHelp);
    }

    public static StatusStripStatusSnapshot Remote(IEnumerable<CanvasNode> remoteMachines)
    {
        var machines = remoteMachines.ToList();
        var connectedCount = machines.Count(node => node.Metadata.HostStatus == HostStatuses.Connected);
        var issueMachines = machines
            .Where(node => node.Metadata.HostStatus == HostStatuses.Unavailable)
            .OrderBy(node => node.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (issueMachines.Count > 0)
        {
            return new StatusStripStatusSnapshot(
                $"{connectedCount} connected, {issueMachines.Count} host issue{(issueMachines.Count == 1 ? "" : "s")}",
                "\uE7BA",
                WarningIcon,
                UnavailableHex,
                string.Join(Environment.NewLine, issueMachines.Select(HostIssueHelpText)));
        }

        return new StatusStripStatusSnapshot(
            $"{connectedCount} remote{(connectedCount == 1 ? "" : "s")} connected",
            "\uE8CE",
            RemoteAntennaIcon,
            SecondaryHex,
            "Remote App Server and tunnel status looks stable.");
    }

    public static string DefaultLocalMessage(string status)
    {
        return NormalizeLocalStatus(status) switch
        {
            HostStatuses.Connected => "Connected",
            HostStatuses.Connecting => "Connecting",
            HostStatuses.Unavailable => "Runtime failed",
            _ => "Not connected"
        };
    }

    public static string NormalizeLocalStatus(string status)
    {
        return status switch
        {
            HostStatuses.Connected => HostStatuses.Connected,
            HostStatuses.Connecting => HostStatuses.Connecting,
            HostStatuses.Unavailable => HostStatuses.Unavailable,
            _ => HostStatuses.Disconnected
        };
    }

    private static string LocalGlyph(string status)
    {
        return status switch
        {
            HostStatuses.Connected => "\uE73E",
            HostStatuses.Connecting => "\uE72C",
            HostStatuses.Unavailable => "\uE7BA",
            _ => "\uEA3A"
        };
    }

    private static string LocalIconKind(string status)
    {
        return status switch
        {
            HostStatuses.Connected => LocalConnectedIcon,
            HostStatuses.Connecting => LocalConnectingIcon,
            HostStatuses.Unavailable => WarningIcon,
            _ => LocalDisconnectedIcon
        };
    }

    private static string LocalColor(string status)
    {
        return status switch
        {
            HostStatuses.Connected => ConnectedHex,
            HostStatuses.Connecting => ConnectingHex,
            HostStatuses.Unavailable => UnavailableHex,
            _ => SecondaryHex
        };
    }

    private static string NormalizeMessage(string? message, string fallback)
    {
        return string.IsNullOrWhiteSpace(message) ? fallback : message.Trim();
    }

    private static string HostIssueHelpText(CanvasNode node)
    {
        return $"{node.Title}: {NormalizeMessage(node.Metadata.HostLastError, "failed")}";
    }
}
