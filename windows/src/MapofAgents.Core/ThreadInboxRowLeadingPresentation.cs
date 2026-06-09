namespace MapofAgents.Core;

public readonly record struct ThreadInboxRowLeadingPresentationSnapshot(
    string ThreadMacSymbolName,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double BackBubbleOpacity);

public static class ThreadInboxRowLeadingPresentation
{
    public const string ThreadMacSymbolName = "bubble.left.and.bubble.right";
    public const double IconWidth = 18;
    public const double IconHeight = 16;
    public const double StrokeThickness = 1.15;
    public const double BackBubbleOpacity = 0.72;

    public static ThreadInboxRowLeadingPresentationSnapshot Resolve()
    {
        return new ThreadInboxRowLeadingPresentationSnapshot(
            ThreadMacSymbolName,
            IconWidth,
            IconHeight,
            StrokeThickness,
            BackBubbleOpacity);
    }
}
