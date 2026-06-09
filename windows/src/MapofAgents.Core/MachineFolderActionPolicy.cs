namespace MapofAgents.Core;

public static class MachineFolderActionPolicy
{
    public static bool CanChooseProjectFolder(CanvasNode node, bool isLocalHost, bool hasRemoteBrowser)
    {
        return node.Kind == NodeKinds.Machine && (isLocalHost || hasRemoteBrowser);
    }

    public static bool CanAddFolderFromMachine(CanvasNode node, bool isLocalHost, bool hasRemoteBrowser)
    {
        return CanChooseProjectFolder(node, isLocalHost, hasRemoteBrowser) ||
            (node.Kind == NodeKinds.Machine && node.Metadata.HostStatus == HostStatuses.Connected);
    }

    public static string? UnavailableReason(CanvasNode node, bool isLocalHost, bool hasRemoteBrowser)
    {
        if (CanAddFolderFromMachine(node, isLocalHost, hasRemoteBrowser))
        {
            return null;
        }

        return node.Kind == NodeKinds.Machine
            ? "Connect this machine before adding a project folder."
            : "Choose a machine before adding a project folder.";
    }
}
