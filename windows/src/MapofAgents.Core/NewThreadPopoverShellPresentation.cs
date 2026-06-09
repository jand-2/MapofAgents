namespace MapofAgents.Core;

public readonly record struct NewThreadPopoverShellPresentationSnapshot(
    double Width,
    double Height,
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    double ShadowTranslationZ);

public static class NewThreadPopoverShellPresentation
{
    public const double Width = 470;
    public const double Height = 620;
    public const string BorderHex = "#24FFFFFF";
    public const double BorderThickness = 1;
    public const double CornerRadius = 8;
    public const double ShadowTranslationZ = 18;

    public static NewThreadPopoverShellPresentationSnapshot Resolve()
    {
        return new NewThreadPopoverShellPresentationSnapshot(
            Width,
            Height,
            BorderHex,
            BorderThickness,
            CornerRadius,
            ShadowTranslationZ);
    }
}
