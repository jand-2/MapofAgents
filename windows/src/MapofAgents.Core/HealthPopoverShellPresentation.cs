namespace MapofAgents.Core;

public readonly record struct HealthPopoverShellPresentationSnapshot(
    double Width,
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    double ShadowTranslationZ);

public static class HealthPopoverShellPresentation
{
    public const double Width = 380;
    public const string BorderHex = "#24FFFFFF";
    public const double BorderThickness = 1;
    public const double CornerRadius = 8;
    public const double ShadowTranslationZ = 18;

    public static HealthPopoverShellPresentationSnapshot Resolve()
    {
        return new HealthPopoverShellPresentationSnapshot(
            Width,
            BorderHex,
            BorderThickness,
            CornerRadius,
            ShadowTranslationZ);
    }
}
