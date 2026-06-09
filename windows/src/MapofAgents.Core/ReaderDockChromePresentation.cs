namespace MapofAgents.Core;

public readonly record struct ReaderDockChromePresentationSnapshot(
    string BackgroundHex,
    string HairlineHex,
    double HairlineThickness);

public static class ReaderDockChromePresentation
{
    public const string BackgroundHex = "#F51D1E20";
    public const string HairlineHex = "#18FFFFFF";
    public const double HairlineThickness = 1;

    public static ReaderDockChromePresentationSnapshot Resolve()
    {
        return new ReaderDockChromePresentationSnapshot(
            BackgroundHex,
            HairlineHex,
            HairlineThickness);
    }
}
