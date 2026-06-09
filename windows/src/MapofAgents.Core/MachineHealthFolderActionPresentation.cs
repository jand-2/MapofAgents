namespace MapofAgents.Core;

public readonly record struct MachineHealthFolderActionPresentationSnapshot(
    bool IsVisible,
    bool CanInvoke,
    double Opacity,
    string ToolTip,
    string AutomationName,
    string MacSymbolName);

public static class MachineHealthFolderActionPresentation
{
    public const string BrowseToolTip = "Browse project folders";
    public const string AddToolTip = "Add folder";
    public const string LocalToolTip = "Use Folder to add a local project.";
    public const string UnavailableToolTip = "Connect this machine before adding a folder.";
    public const string BrowseMacSymbolName = "folder";
    public const string AddMacSymbolName = "folder.badge.plus";
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;

    public static MachineHealthFolderActionPresentationSnapshot Resolve(
        bool isLocal,
        string? hostStatus,
        bool hasRemoteBrowser)
    {
        if (isLocal)
        {
            return new MachineHealthFolderActionPresentationSnapshot(
                IsVisible: false,
                CanInvoke: false,
                AvailableOpacity,
                LocalToolTip,
                LocalToolTip,
                AddMacSymbolName);
        }

        if (hostStatus != HostStatuses.Connected)
        {
            return new MachineHealthFolderActionPresentationSnapshot(
                IsVisible: true,
                CanInvoke: false,
                UnavailableOpacity,
                UnavailableToolTip,
                UnavailableToolTip,
                hasRemoteBrowser ? BrowseMacSymbolName : AddMacSymbolName);
        }

        return new MachineHealthFolderActionPresentationSnapshot(
            IsVisible: true,
            CanInvoke: true,
            AvailableOpacity,
            hasRemoteBrowser ? BrowseToolTip : AddToolTip,
            hasRemoteBrowser ? BrowseToolTip : AddToolTip,
            hasRemoteBrowser ? BrowseMacSymbolName : AddMacSymbolName);
    }
}
