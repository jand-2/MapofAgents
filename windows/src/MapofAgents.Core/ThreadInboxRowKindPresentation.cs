namespace MapofAgents.Core;

public readonly record struct ThreadInboxRowKindPresentationSnapshot(
    string ThreadMacSymbolName,
    double IconWidth,
    double IconHeight,
    double StrokeThickness);

public static class ThreadInboxRowKindPresentation
{
    public const string ThreadMacSymbolName = "bubble.left";
    public const double IconWidth = 14;
    public const double IconHeight = 12;
    public const double StrokeThickness = 1.1;

    public static ThreadInboxRowKindPresentationSnapshot Resolve()
    {
        return new ThreadInboxRowKindPresentationSnapshot(
            ThreadMacSymbolName,
            IconWidth,
            IconHeight,
            StrokeThickness);
    }
}
