namespace MapofAgents.Core;

public readonly record struct ToolbarHealthPresentationSnapshot(
    string MacSymbolName,
    bool ShowsHeartTextSquareIcon,
    string IconHex,
    double Opacity,
    string ToolTip,
    double IconWidth,
    double IconHeight,
    double StrokeThickness);

public readonly record struct ToolbarHealthMenuPresentationSnapshot(
    string RefreshIconKind,
    string RefreshMacSymbolName,
    string DiagnosticsIconKind,
    string DiagnosticsMacSymbolName,
    string RecoveryIconKind,
    string RecoveryMacSymbolName,
    string LogsIconKind,
    string LogsMacSymbolName,
    double IconSize);

public static class ToolbarHealthPresentation
{
    public const string HeartTextSquareMacSymbolName = "heart.text.square";
    public const string RefreshingMacSymbolName = "arrow.triangle.2.circlepath";
    public const string IconHex = "#D7DCE5";
    public const string RefreshIcon = "arrowClockwise";
    public const string DiagnosticsIcon = "stethoscope";
    public const string RecoveryIcon = "crossCase";
    public const string LogsIcon = "docTextMagnifyingglass";
    public const string RefreshMacSymbolName = "arrow.clockwise";
    public const string DiagnosticsMacSymbolName = "stethoscope";
    public const string RecoveryMacSymbolName = "cross.case";
    public const string LogsMacSymbolName = "doc.text.magnifyingglass";
    public const double IconWidth = 16;
    public const double IconHeight = 14;
    public const double IconStrokeThickness = 1.1;
    public const double MenuIconSize = 16;

    public static ToolbarHealthPresentationSnapshot Resolve(bool isRefreshing)
    {
        return isRefreshing
            ? new ToolbarHealthPresentationSnapshot(
                RefreshingMacSymbolName,
                ShowsHeartTextSquareIcon: false,
                IconHex,
                Opacity: 0.74,
                ToolTip: "Connection refresh is already running.",
                IconWidth,
                IconHeight,
                IconStrokeThickness)
            : new ToolbarHealthPresentationSnapshot(
                HeartTextSquareMacSymbolName,
                ShowsHeartTextSquareIcon: true,
                IconHex,
                Opacity: 1.0,
                ToolTip: "Refresh machine and runtime health",
                IconWidth,
                IconHeight,
                IconStrokeThickness);
    }

    public static ToolbarHealthMenuPresentationSnapshot ResolveMenu()
    {
        return new ToolbarHealthMenuPresentationSnapshot(
            RefreshIcon,
            RefreshMacSymbolName,
            DiagnosticsIcon,
            DiagnosticsMacSymbolName,
            RecoveryIcon,
            RecoveryMacSymbolName,
            LogsIcon,
            LogsMacSymbolName,
            MenuIconSize);
    }
}
