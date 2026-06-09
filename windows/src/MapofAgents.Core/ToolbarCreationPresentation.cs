namespace MapofAgents.Core;

public readonly record struct ToolbarCreationPresentationSnapshot(
    string FolderMacSymbolName,
    string ThreadMacSymbolName,
    string FolderStrokeHex,
    string FolderBadgeFillHex,
    string FolderPlusHex,
    string ThreadStrokeHex,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double ThreadStrokeThickness,
    double BadgeSize,
    double BadgeX,
    double BadgeY,
    double PlusStrokeThickness,
    string FolderAccessibilityName,
    string ThreadAccessibilityName);

public static class ToolbarCreationPresentation
{
    public const string FolderMacSymbolName = "folder.badge.plus";
    public const string ThreadMacSymbolName = "plus.bubble";
    public const string FolderStrokeHex = "#D7DCE5";
    public const string FolderBadgeFillHex = "#D7DCE5";
    public const string FolderPlusHex = "#1D1E20";
    public const string ThreadStrokeHex = "#FFFFFFFF";
    public const double IconWidth = 18;
    public const double IconHeight = 16;
    public const double StrokeThickness = 1.15;
    public const double ThreadStrokeThickness = 1.25;
    public const double BadgeSize = 5.8;
    public const double BadgeX = 12;
    public const double BadgeY = 1;
    public const double PlusStrokeThickness = 1.15;
    public const string FolderAccessibilityName = "Add folder";
    public const string ThreadAccessibilityName = "Create Codex thread";

    public static ToolbarCreationPresentationSnapshot Resolve()
    {
        return new ToolbarCreationPresentationSnapshot(
            FolderMacSymbolName,
            ThreadMacSymbolName,
            FolderStrokeHex,
            FolderBadgeFillHex,
            FolderPlusHex,
            ThreadStrokeHex,
            IconWidth,
            IconHeight,
            StrokeThickness,
            ThreadStrokeThickness,
            BadgeSize,
            BadgeX,
            BadgeY,
            PlusStrokeThickness,
            FolderAccessibilityName,
            ThreadAccessibilityName);
    }
}
