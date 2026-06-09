namespace MapofAgents.Core;

public readonly record struct PairingMessagePresentationSnapshot(
    string AccentHex,
    string BackgroundHex,
    string BorderHex,
    string DetailForegroundHex);

public static class PairingMessagePresentation
{
    public const string StartingTitle = "Starting pairing host";
    public const string StartingAccentHex = "#0A84FF";
    public const string StartingBackgroundHex = "#1A0A84FF";
    public const string StartingBorderHex = "#260A84FF";
    public const string FailureAccentHex = "#B42318";
    public const string FailureBackgroundHex = "#1AB42318";
    public const string FailureBorderHex = "#26B42318";
    public const string FailureDetailForegroundHex = "#FFB4AB";
    public const string DefaultDetailForegroundHex = "#D7DCE5";

    public static PairingMessagePresentationSnapshot Resolve(
        string accentHex,
        string backgroundHex,
        string borderHex)
    {
        var detailForeground = string.Equals(accentHex, FailureAccentHex, StringComparison.OrdinalIgnoreCase)
            ? FailureDetailForegroundHex
            : DefaultDetailForegroundHex;

        return new PairingMessagePresentationSnapshot(
            accentHex,
            backgroundHex,
            borderHex,
            detailForeground);
    }

    public static string? HeaderSubtitle(string? hostName)
    {
        return string.IsNullOrWhiteSpace(hostName) ? null : hostName.Trim();
    }
}
