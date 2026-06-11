namespace MapofAgents.Core;

public readonly record struct MachineDiscoveryActionPresentationSnapshot(
    bool CanInvoke,
    double Opacity,
    string ToolTip,
    string AutomationName);

public static class MachineDiscoveryActionPresentation
{
    public const string ConnectToolTip = "Start remote App Server and connect through SSH";
    public const string SetupUnavailableReason = "This Codex remote needs SSH setup before it can connect.";
    public const string BusyUnavailableReason = "Remote diagnostics are already running.";
    public const string FillEndpointToolTip = "Fill a manual WebSocket endpoint";
    public const string FillEndpointUnavailableReason = "This tailnet entry does not expose a usable App Server endpoint.";
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;

    public static MachineDiscoveryActionPresentationSnapshot ConnectCodexRemote(
        bool isConnectable,
        bool isBusy)
    {
        return CodexRemoteAction(
            isConnectable,
            isBusy,
            ConnectToolTip,
            "Connect Codex remote");
    }

    public static MachineDiscoveryActionPresentationSnapshot FillEndpoint(bool hasEndpoint)
    {
        return hasEndpoint
            ? new MachineDiscoveryActionPresentationSnapshot(
                CanInvoke: true,
                AvailableOpacity,
                FillEndpointToolTip,
                "Use remote endpoint")
            : new MachineDiscoveryActionPresentationSnapshot(
                CanInvoke: false,
                UnavailableOpacity,
                FillEndpointUnavailableReason,
                "Use remote endpoint");
    }

    private static MachineDiscoveryActionPresentationSnapshot CodexRemoteAction(
        bool isConnectable,
        bool isBusy,
        string availableToolTip,
        string automationName)
    {
        if (isBusy)
        {
            return new MachineDiscoveryActionPresentationSnapshot(
                CanInvoke: false,
                UnavailableOpacity,
                BusyUnavailableReason,
                automationName);
        }

        if (!isConnectable)
        {
            return new MachineDiscoveryActionPresentationSnapshot(
                CanInvoke: false,
                UnavailableOpacity,
                SetupUnavailableReason,
                automationName);
        }

        return new MachineDiscoveryActionPresentationSnapshot(
            CanInvoke: true,
            AvailableOpacity,
            availableToolTip,
            automationName);
    }
}
