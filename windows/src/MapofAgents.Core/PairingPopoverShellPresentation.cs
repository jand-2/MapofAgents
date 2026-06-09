namespace MapofAgents.Core;

public readonly record struct PairingPopoverShellPresentationSnapshot(
    double Width,
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    double ShadowTranslationZ);

public static class PairingPopoverShellPresentation
{
    public const double Width = 470;
    public const string BorderHex = "#24FFFFFF";
    public const double BorderThickness = 1;
    public const double CornerRadius = 8;
    public const double ShadowTranslationZ = 18;

    public static PairingPopoverShellPresentationSnapshot Resolve()
    {
        return new PairingPopoverShellPresentationSnapshot(
            Width,
            BorderHex,
            BorderThickness,
            CornerRadius,
            ShadowTranslationZ);
    }
}
