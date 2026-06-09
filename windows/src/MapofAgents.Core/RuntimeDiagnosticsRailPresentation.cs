namespace MapofAgents.Core;

public readonly record struct RuntimeDiagnosticsRailItemPresentationSnapshot(
    string StatusLabel,
    string Glyph,
    string MacSymbolName,
    bool UsesPendingCircleIcon,
    bool UsesRunningArrowsIcon,
    bool UsesFilledCheckIcon,
    bool UsesFilledXIcon,
    bool UsesFilledWarningIcon,
    string ForegroundHex,
    double ContentSpacing,
    double RowColumnSpacing,
    double RowVerticalPadding,
    double IconColumnWidth,
    double IconFontSize,
    double FilledStatusIconSize,
    double FilledStatusIconStrokeThickness,
    double DetailStackSpacing,
    double TitleFontSize,
    double DetailFontSize,
    string DetailForegroundHex,
    int DetailLineLimit,
    bool DetailAllowsWrapping,
    string DetailTrimmingMode);

public static class RuntimeDiagnosticsRailPresentation
{
    public const double ContentSpacing = 10;
    public const double RowColumnSpacing = 8;
    public const double RowVerticalPadding = 0;
    public const double IconColumnWidth = 16;
    public const double IconFontSize = 13;
    public const double FilledStatusIconSize = 13;
    public const double FilledStatusIconStrokeThickness = 1.45;
    public const double DetailStackSpacing = 1;
    public const double TitleFontSize = 12;
    public const double DetailFontSize = 11;
    public const int DetailLineLimit = 1;
    public const bool DetailAllowsWrapping = false;
    public const string DetailTrimmingMode = "CharacterEllipsis";
    public const string DetailForegroundHex = ThreadInboxPresentation.SecondaryHex;
    public const string PendingForegroundHex = ThreadInboxPresentation.SecondaryHex;
    public const string RunningForegroundHex = ThreadInboxPresentation.BlueHex;
    public const string PassedForegroundHex = ThreadInboxPresentation.GreenHex;
    public const string WarningForegroundHex = ThreadInboxPresentation.OrangeHex;
    public const string FailedForegroundHex = ThreadInboxPresentation.RedHex;

    public static RuntimeDiagnosticsRailItemPresentationSnapshot Resolve(string? status)
    {
        var normalized = NormalizeStatus(status);
        return new RuntimeDiagnosticsRailItemPresentationSnapshot(
            StatusLabel(normalized),
            GlyphFor(normalized),
            MacSymbolNameFor(normalized),
            normalized == RuntimeDiagnosticStatuses.Pending,
            normalized == RuntimeDiagnosticStatuses.Running,
            normalized == RuntimeDiagnosticStatuses.Passed,
            normalized == RuntimeDiagnosticStatuses.Failed,
            normalized == RuntimeDiagnosticStatuses.Warning,
            ForegroundHexFor(normalized),
            ContentSpacing,
            RowColumnSpacing,
            RowVerticalPadding,
            IconColumnWidth,
            IconFontSize,
            FilledStatusIconSize,
            FilledStatusIconStrokeThickness,
            DetailStackSpacing,
            TitleFontSize,
            DetailFontSize,
            DetailForegroundHex,
            DetailLineLimit,
            DetailAllowsWrapping,
            DetailTrimmingMode);
    }

    private static string NormalizeStatus(string? status)
    {
        return status switch
        {
            RuntimeDiagnosticStatuses.Running => RuntimeDiagnosticStatuses.Running,
            RuntimeDiagnosticStatuses.Passed => RuntimeDiagnosticStatuses.Passed,
            RuntimeDiagnosticStatuses.Warning => RuntimeDiagnosticStatuses.Warning,
            RuntimeDiagnosticStatuses.Failed => RuntimeDiagnosticStatuses.Failed,
            _ => RuntimeDiagnosticStatuses.Pending
        };
    }

    private static string StatusLabel(string status)
    {
        return status switch
        {
            RuntimeDiagnosticStatuses.Running => "Running",
            RuntimeDiagnosticStatuses.Passed => "Passed",
            RuntimeDiagnosticStatuses.Warning => "Warning",
            RuntimeDiagnosticStatuses.Failed => "Failed",
            _ => "Pending"
        };
    }

    private static string GlyphFor(string status)
    {
        return status switch
        {
            RuntimeDiagnosticStatuses.Running => "\uE895",
            RuntimeDiagnosticStatuses.Passed => "\uE930",
            RuntimeDiagnosticStatuses.Warning => "\uE7BA",
            RuntimeDiagnosticStatuses.Failed => "\uEA39",
            _ => "\uEA3A"
        };
    }

    private static string MacSymbolNameFor(string status)
    {
        return status switch
        {
            RuntimeDiagnosticStatuses.Running => "arrow.triangle.2.circlepath",
            RuntimeDiagnosticStatuses.Passed => "checkmark.circle.fill",
            RuntimeDiagnosticStatuses.Warning => "exclamationmark.triangle.fill",
            RuntimeDiagnosticStatuses.Failed => "xmark.circle.fill",
            _ => "circle"
        };
    }

    private static string ForegroundHexFor(string status)
    {
        return status switch
        {
            RuntimeDiagnosticStatuses.Running => RunningForegroundHex,
            RuntimeDiagnosticStatuses.Passed => PassedForegroundHex,
            RuntimeDiagnosticStatuses.Warning => WarningForegroundHex,
            RuntimeDiagnosticStatuses.Failed => FailedForegroundHex,
            _ => PendingForegroundHex
        };
    }
}
