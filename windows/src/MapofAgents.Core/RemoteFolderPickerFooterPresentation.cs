namespace MapofAgents.Core;

public readonly record struct RemoteFolderPickerFooterPresentationSnapshot(
    string SelectedCurrentPath,
    string AddLabel,
    string AddGlyph,
    string AutomationName,
    string? UnavailableReason,
    bool CanAddCurrentFolder);

public static class RemoteFolderPickerFooterPresentation
{
    public const string AddLabel = "Add";
    public const string AddGlyph = "\uE73E";
    public const string AddAutomationName = "Add current folder";
    public const string EmptySelectionReason = "Choose a folder before adding it.";

    public static RemoteFolderPickerFooterPresentationSnapshot Resolve(
        string? listingPath,
        string? draftPath)
    {
        var selectedPath = (listingPath ?? draftPath ?? string.Empty).Trim();
        var canAddCurrentFolder = !string.IsNullOrWhiteSpace(selectedPath);

        return new RemoteFolderPickerFooterPresentationSnapshot(
            selectedPath,
            AddLabel,
            AddGlyph,
            AddAutomationName,
            canAddCurrentFolder ? null : EmptySelectionReason,
            canAddCurrentFolder);
    }
}
