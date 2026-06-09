namespace MapofAgents.Core;

public readonly record struct ThreadPopoverShellPresentationSnapshot(
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    double ShadowTranslationZ,
    double HeaderColumnSpacing,
    double HeaderActionSpacing,
    double HeaderControlsLeftInset);

public static class ThreadPopoverShellPresentation
{
    public const string BorderHex = "#24FFFFFF";
    public const double BorderThickness = 1;
    public const double CornerRadius = 8;
    public const double ShadowTranslationZ = 18;
    public const double HeaderColumnSpacing = 10;
    public const double HeaderActionSpacing = 10;
    public const double HeaderControlsLeftInset = 2;

    public static ThreadPopoverShellPresentationSnapshot Resolve()
    {
        return new ThreadPopoverShellPresentationSnapshot(
            BorderHex,
            BorderThickness,
            CornerRadius,
            ShadowTranslationZ,
            HeaderColumnSpacing,
            HeaderActionSpacing,
            HeaderControlsLeftInset);
    }

    public static ThreadPopoverShellPresentationSnapshot ResolveReaderTile()
    {
        return Resolve();
    }
}
