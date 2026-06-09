namespace MapofAgents.Core;

public static class MachineRecoveryPolicy
{
    public static bool NeedsRecovery(CanvasNode node, bool isLocalHost)
    {
        if (node.Kind != NodeKinds.Machine)
        {
            return false;
        }

        var status = node.Metadata.HostStatus ?? HostStatuses.Disconnected;
        if (status is HostStatuses.Unavailable or HostStatuses.Connecting)
        {
            return true;
        }

        return status == HostStatuses.Disconnected &&
            !isLocalHost &&
            !string.IsNullOrWhiteSpace(node.Metadata.AppServerEndpointUrl);
    }
}
