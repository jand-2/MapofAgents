namespace MapofAgents.Core;

public readonly record struct MachineHealthPresentationSnapshot(
    string Text,
    string Glyph,
    string MacSymbolName,
    bool UsesFilledCheckIcon,
    string ForegroundHex,
    string BackgroundHex,
    string BorderHex,
    double IconColumnWidth,
    double FilledCheckIconSize,
    double FilledCheckStrokeThickness);

public static class MachineHealthPresentation
{
    public const string SecondaryHex = "#A7B0BF";
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string SecondaryBackgroundHex = "#1FA7B0BF";
    public const string BlueBackgroundHex = "#1F0A84FF";
    public const string GreenBackgroundHex = "#1F30D158";
    public const string OrangeBackgroundHex = "#1FFF9F0A";
    public const string SecondaryBorderHex = "#2EA7B0BF";
    public const string BlueBorderHex = "#2E0A84FF";
    public const string GreenBorderHex = "#2E30D158";
    public const string OrangeBorderHex = "#2EFF9F0A";
    public const string ConnectedGlyph = "\uE73E";
    public const string ConnectingGlyph = "\uE895";
    public const string DisconnectedGlyph = "\uEA3A";
    public const string FailedGlyph = "\uE7BA";
    public const double IconColumnWidth = 18;
    public const double FilledCheckIconSize = 13;
    public const double FilledCheckStrokeThickness = 1.45;

    public static MachineHealthPresentationSnapshot Resolve(string? hostStatus)
    {
        return hostStatus switch
        {
            HostStatuses.Connected => Snapshot(
                "connected",
                ConnectedGlyph,
                "checkmark.circle.fill",
                usesFilledCheckIcon: true,
                GreenHex,
                GreenBackgroundHex,
                GreenBorderHex),
            HostStatuses.Connecting => Snapshot(
                "connecting",
                ConnectingGlyph,
                "arrow.triangle.2.circlepath",
                usesFilledCheckIcon: false,
                BlueHex,
                BlueBackgroundHex,
                BlueBorderHex),
            HostStatuses.Unavailable => Snapshot(
                "failed",
                FailedGlyph,
                "exclamationmark.triangle.fill",
                usesFilledCheckIcon: false,
                OrangeHex,
                OrangeBackgroundHex,
                OrangeBorderHex),
            _ => Snapshot(
                "offline",
                DisconnectedGlyph,
                "circle",
                usesFilledCheckIcon: false,
                SecondaryHex,
                SecondaryBackgroundHex,
                SecondaryBorderHex)
        };
    }

    private static MachineHealthPresentationSnapshot Snapshot(
        string text,
        string glyph,
        string macSymbolName,
        bool usesFilledCheckIcon,
        string foregroundHex,
        string backgroundHex,
        string borderHex)
    {
        return new MachineHealthPresentationSnapshot(
            text,
            glyph,
            macSymbolName,
            usesFilledCheckIcon,
            foregroundHex,
            backgroundHex,
            borderHex,
            IconColumnWidth,
            FilledCheckIconSize,
            FilledCheckStrokeThickness);
    }
}
