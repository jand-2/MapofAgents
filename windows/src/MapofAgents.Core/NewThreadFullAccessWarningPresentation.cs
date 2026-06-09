namespace MapofAgents.Core;

public readonly record struct NewThreadFullAccessWarningPresentationSnapshot(
    string Text,
    string MacSymbolName,
    string IconHex,
    string ExclamationHex,
    string BackgroundHex,
    string BorderHex,
    double BorderThickness,
    double IconWidth,
    double IconHeight,
    double ExclamationStrokeThickness);

public static class NewThreadFullAccessWarningPresentation
{
    public const string MacSymbolName = "exclamationmark.triangle.fill";
    public const string IconHex = "#FFD60A";
    public const string ExclamationHex = "#1F2128";
    public const string BackgroundHex = "#1AFFD60A";
    public const string BorderHex = "#00FFFFFF";
    public const double BorderThickness = 0;
    public const double IconWidth = 15;
    public const double IconHeight = 14;
    public const double ExclamationStrokeThickness = 1.45;

    public static NewThreadFullAccessWarningPresentationSnapshot Resolve(bool isRemoteTarget)
    {
        return new NewThreadFullAccessWarningPresentationSnapshot(
            isRemoteTarget
                ? "Full Access disables filesystem sandboxing on the remote target and can read or change files outside the selected folder."
                : "Full Access disables filesystem sandboxing and can read or change files outside the selected folder.",
            MacSymbolName,
            IconHex,
            ExclamationHex,
            BackgroundHex,
            BorderHex,
            BorderThickness,
            IconWidth,
            IconHeight,
            ExclamationStrokeThickness);
    }
}
