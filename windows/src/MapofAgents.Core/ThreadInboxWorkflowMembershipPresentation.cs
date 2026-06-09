namespace MapofAgents.Core;

public readonly record struct ThreadInboxWorkflowMembershipPresentationSnapshot(
    string IconKind,
    string MacSymbolName,
    string Glyph,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double SecondaryOpacity);

public static class ThreadInboxWorkflowMembershipPresentation
{
    public const string RectangleGroupIcon = "rectangleGroup";
    public const string SquareStack3dUpIcon = "squareStack3dUp";
    public const string DashedRectangleIcon = "dashedRectangle";
    public const string RectangleSwapIcon = "rectangleSwap";

    public const string RectangleGroupMacSymbolName = "rectangle.3.group";
    public const string SquareStack3dUpMacSymbolName = "square.stack.3d.up";
    public const string DashedRectangleMacSymbolName = "rectangle.dashed";
    public const string RectangleSwapMacSymbolName = "rectangle.2.swap";

    public const string RectangleGroupGlyph = "\uECA5";
    public const string SquareStack3dUpGlyph = "\uE8B7";
    public const string DashedRectangleGlyph = "\uE711";
    public const string RectangleSwapGlyph = "\uE8AB";

    public const double IconWidth = 14;
    public const double IconHeight = 12;
    public const double StrokeThickness = 1.0;
    public const double SecondaryOpacity = 0.68;

    public static ThreadInboxWorkflowMembershipPresentationSnapshot Resolve(
        bool hasActiveWorkflowMembership,
        int workflowMembershipCount)
    {
        if (hasActiveWorkflowMembership)
        {
            return new ThreadInboxWorkflowMembershipPresentationSnapshot(
                RectangleGroupIcon,
                RectangleGroupMacSymbolName,
                RectangleGroupGlyph,
                IconWidth,
                IconHeight,
                StrokeThickness,
                SecondaryOpacity);
        }

        return workflowMembershipCount switch
        {
            <= 0 => new ThreadInboxWorkflowMembershipPresentationSnapshot(
                DashedRectangleIcon,
                DashedRectangleMacSymbolName,
                DashedRectangleGlyph,
                IconWidth,
                IconHeight,
                StrokeThickness,
                SecondaryOpacity),
            1 => new ThreadInboxWorkflowMembershipPresentationSnapshot(
                RectangleSwapIcon,
                RectangleSwapMacSymbolName,
                RectangleSwapGlyph,
                IconWidth,
                IconHeight,
                StrokeThickness,
                SecondaryOpacity),
            _ => new ThreadInboxWorkflowMembershipPresentationSnapshot(
                SquareStack3dUpIcon,
                SquareStack3dUpMacSymbolName,
                SquareStack3dUpGlyph,
                IconWidth,
                IconHeight,
                StrokeThickness,
                SecondaryOpacity)
        };
    }
}
