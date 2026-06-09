namespace MapofAgents.Core;

public readonly record struct ToolbarWorkflowPresentationSnapshot(
    string MacSymbolName,
    bool UsesRectangleGroupIcon,
    string StrokeHex,
    string ChevronStrokeHex,
    string ToolTip,
    string DefaultTitle,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double ChevronWidth,
    double ChevronHeight,
    double ChevronStrokeThickness);

public readonly record struct ToolbarWorkflowMenuPresentationSnapshot(
    string ActiveWorkflowIconKind,
    string ActiveWorkflowMacSymbolName,
    string InactiveWorkflowIconKind,
    string InactiveWorkflowMacSymbolName,
    string NewWorkflowIconKind,
    string NewWorkflowMacSymbolName,
    string RenameIconKind,
    string RenameMacSymbolName,
    string DuplicateIconKind,
    string DuplicateMacSymbolName,
    string DeleteIconKind,
    string DeleteMacSymbolName,
    double IconSize);

public readonly record struct ToolbarWorkflowNameEditorPresentationSnapshot(
    string Mode,
    string Title,
    string ActionTitle,
    string IconKind,
    string MacSymbolName,
    string IconHex,
    string BackgroundHex,
    double IconSize,
    string CloseGlyph,
    string CloseMacSymbolName,
    double CloseButtonSize,
    double CloseIconSize);

public static class ToolbarWorkflowPresentation
{
    public const string MacSymbolName = "rectangle.3.group";
    public const string StrokeHex = "#D7DCE5";
    public const string ChevronStrokeHex = "#D7DCE5";
    public const string DefaultTitle = "Workflow";
    public const string InitialWorkflowName = "Main Workflow";
    public const string NameEditorCreateMode = "create";
    public const string NameEditorRenameMode = "rename";
    public const string NameEditorDuplicateMode = "duplicate";
    public const string ActiveWorkflowIcon = "checkmark";
    public const string InactiveWorkflowIcon = "circle";
    public const string NewWorkflowIcon = "plus";
    public const string RenameIcon = "pencil";
    public const string DuplicateIcon = "docOnDoc";
    public const string DeleteIcon = "trash";
    public const string ActiveWorkflowMacSymbolName = "checkmark";
    public const string InactiveWorkflowMacSymbolName = "circle";
    public const string NewWorkflowMacSymbolName = "plus";
    public const string RenameMacSymbolName = "pencil";
    public const string DuplicateMacSymbolName = "doc.on.doc";
    public const string DeleteMacSymbolName = "trash";
    public const double IconWidth = 17;
    public const double IconHeight = 15;
    public const double StrokeThickness = 1;
    public const double ChevronWidth = 8;
    public const double ChevronHeight = 7;
    public const double ChevronStrokeThickness = 1.15;
    public const double MenuIconSize = 16;
    public const double NameEditorIconSize = 16;
    public const string NameEditorIconHex = "#0A84FF";
    public const string NameEditorBackgroundHex = "#1A0A84FF";
    public const string NameEditorCloseGlyph = "\uE711";
    public const string NameEditorCloseMacSymbolName = "xmark";
    public const double NameEditorCloseButtonSize = 24;
    public const double NameEditorCloseIconSize = 12;

    public static ToolbarWorkflowPresentationSnapshot Resolve()
    {
        return new ToolbarWorkflowPresentationSnapshot(
            MacSymbolName,
            UsesRectangleGroupIcon: true,
            StrokeHex,
            ChevronStrokeHex,
            ToolTip: "Workflow",
            DefaultTitle,
            IconWidth,
            IconHeight,
            StrokeThickness,
            ChevronWidth,
            ChevronHeight,
            ChevronStrokeThickness);
    }

    public static string DisplayTitle(string? title)
    {
        return string.IsNullOrWhiteSpace(title)
            ? DefaultTitle
            : title.Trim();
    }

    public static string DisplayActiveTitle(string? activeWorkflowName, string? graphTitle)
    {
        return string.IsNullOrWhiteSpace(activeWorkflowName)
            ? DisplayTitle(graphTitle)
            : activeWorkflowName.Trim();
    }

    public static ToolbarWorkflowMenuPresentationSnapshot ResolveMenu()
    {
        return new ToolbarWorkflowMenuPresentationSnapshot(
            ActiveWorkflowIcon,
            ActiveWorkflowMacSymbolName,
            InactiveWorkflowIcon,
            InactiveWorkflowMacSymbolName,
            NewWorkflowIcon,
            NewWorkflowMacSymbolName,
            RenameIcon,
            RenameMacSymbolName,
            DuplicateIcon,
            DuplicateMacSymbolName,
            DeleteIcon,
            DeleteMacSymbolName,
            MenuIconSize);
    }

    public static ToolbarWorkflowNameEditorPresentationSnapshot ResolveNameEditor(string mode)
    {
        var normalized = mode.Trim().ToLowerInvariant();
        return normalized switch
        {
            NameEditorCreateMode => NameEditor(
                normalized,
                "New Workflow",
                "Create",
                NewWorkflowIcon,
                NewWorkflowMacSymbolName),
            NameEditorRenameMode => NameEditor(
                normalized,
                "Rename Workflow",
                "Rename",
                RenameIcon,
                RenameMacSymbolName),
            NameEditorDuplicateMode => NameEditor(
                normalized,
                "Save Workflow Copy",
                "Save Copy",
                DuplicateIcon,
                DuplicateMacSymbolName),
            _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unknown workflow name editor mode.")
        };
    }

    private static ToolbarWorkflowNameEditorPresentationSnapshot NameEditor(
        string mode,
        string title,
        string actionTitle,
        string iconKind,
        string macSymbolName)
    {
        return new ToolbarWorkflowNameEditorPresentationSnapshot(
            mode,
            title,
            actionTitle,
            iconKind,
            macSymbolName,
            NameEditorIconHex,
            NameEditorBackgroundHex,
            NameEditorIconSize,
            NameEditorCloseGlyph,
            NameEditorCloseMacSymbolName,
            NameEditorCloseButtonSize,
            NameEditorCloseIconSize);
    }
}
