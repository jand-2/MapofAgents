namespace MapofAgents.Core;

public readonly record struct GraphNodeFolderActionPresentationSnapshot(
    string ToolTip,
    string CssClass,
    bool IsAriaDisabled,
    double Opacity);

public readonly record struct GraphNodeFolderActionWebConfig(
    string ChooseProjectToolTip,
    string AddProjectToolTip,
    string UnavailableToolTip,
    string UnavailableCssClass,
    bool UnavailableAriaDisabled,
    double AvailableOpacity,
    double UnavailableOpacity);

public static class GraphNodeActionPresentation
{
    public const string ChooseProjectToolTip = "Choose project from this machine";
    public const string AddProjectToolTip = "Add project from this machine";
    public const string UnavailableToolTip = "Connect this machine before adding a project folder.";
    public const string UnavailableCssClass = "unavailable";
    public const bool UnavailableAriaDisabled = true;
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;

    public static GraphNodeFolderActionPresentationSnapshot FolderAction(
        bool canChooseProjectFolder,
        bool canAddFolderFromMachine)
    {
        if (canChooseProjectFolder)
        {
            return new GraphNodeFolderActionPresentationSnapshot(
                ChooseProjectToolTip,
                CssClass: string.Empty,
                IsAriaDisabled: false,
                AvailableOpacity);
        }

        if (canAddFolderFromMachine)
        {
            return new GraphNodeFolderActionPresentationSnapshot(
                AddProjectToolTip,
                CssClass: string.Empty,
                IsAriaDisabled: false,
                AvailableOpacity);
        }

        return new GraphNodeFolderActionPresentationSnapshot(
            UnavailableToolTip,
            UnavailableCssClass,
            UnavailableAriaDisabled,
            UnavailableOpacity);
    }

    public static GraphNodeFolderActionWebConfig FolderActionWebConfig()
    {
        return new GraphNodeFolderActionWebConfig(
            ChooseProjectToolTip,
            AddProjectToolTip,
            UnavailableToolTip,
            UnavailableCssClass,
            UnavailableAriaDisabled,
            AvailableOpacity,
            UnavailableOpacity);
    }
}
