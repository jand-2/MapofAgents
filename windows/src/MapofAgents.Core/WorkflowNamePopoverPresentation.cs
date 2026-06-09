namespace MapofAgents.Core;

public readonly record struct WorkflowNamePopoverPresentationSnapshot(
    double Width,
    double Padding,
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    double ShadowTranslationZ,
    double SurfaceSpacing,
    double HeaderSpacing,
    double HeaderIconTileSize,
    double HeaderIconCornerRadius,
    double HeaderTitleFontSize,
    double CloseButtonSize,
    double CloseIconFontSize,
    double ActionSpacing);

public static class WorkflowNamePopoverPresentation
{
    public const double Width = 340;
    public const double Padding = 14;
    public const string BorderHex = "#24FFFFFF";
    public const double BorderThickness = 1;
    public const double CornerRadius = 8;
    public const double ShadowTranslationZ = 18;
    public const double SurfaceSpacing = 14;
    public const double HeaderSpacing = 10;
    public const double HeaderIconTileSize = 26;
    public const double HeaderIconCornerRadius = 6;
    public const double HeaderTitleFontSize = 16;
    public const double CloseButtonSize = 24;
    public const double CloseIconFontSize = 12;
    public const double ActionSpacing = 8;

    public static WorkflowNamePopoverPresentationSnapshot Resolve()
    {
        return new WorkflowNamePopoverPresentationSnapshot(
            Width,
            Padding,
            BorderHex,
            BorderThickness,
            CornerRadius,
            ShadowTranslationZ,
            SurfaceSpacing,
            HeaderSpacing,
            HeaderIconTileSize,
            HeaderIconCornerRadius,
            HeaderTitleFontSize,
            CloseButtonSize,
            CloseIconFontSize,
            ActionSpacing);
    }
}
