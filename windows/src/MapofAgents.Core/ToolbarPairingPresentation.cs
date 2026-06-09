namespace MapofAgents.Core;

public readonly record struct ToolbarPairingPresentationSnapshot(
    string MacSymbolName,
    string IconHex,
    string ToolTip,
    string AccessibilityName,
    double IconSize,
    double FinderSize,
    double InnerFinderSize,
    double ModuleSize);

public static class ToolbarPairingPresentation
{
    public const string MacSymbolName = "qrcode";
    public const string IconHex = "#D7DCE5";
    public const string ToolTip = "Pair an iPhone with this Windows PC";
    public const string AccessibilityName = "Pair";
    public const double IconSize = 15;
    public const double FinderSize = 4.8;
    public const double InnerFinderSize = 1.8;
    public const double ModuleSize = 1.35;

    public static ToolbarPairingPresentationSnapshot Resolve()
    {
        return new ToolbarPairingPresentationSnapshot(
            MacSymbolName,
            IconHex,
            ToolTip,
            AccessibilityName,
            IconSize,
            FinderSize,
            InnerFinderSize,
            ModuleSize);
    }
}
