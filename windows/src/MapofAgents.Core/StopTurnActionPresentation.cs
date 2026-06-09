namespace MapofAgents.Core;

public readonly record struct StopTurnActionPresentationSnapshot(
    string ActiveMacSymbolName,
    string StoppingMacSymbolName,
    string WindowsGlyph,
    string ForegroundHex,
    string BackgroundHex,
    string BorderHex,
    string ToolTip,
    string AccessibilityName);

public readonly record struct StopTurnActionAvailability(
    bool IsVisible,
    bool IsButtonEnabled,
    bool CanInvoke,
    bool IsStoppingTurn,
    string WindowsGlyph,
    double Opacity,
    string ToolTip,
    string AccessibilityName,
    string AccessibilityHint,
    string? UnavailableReason);

public static class StopTurnActionPresentation
{
    public const string ActiveMacSymbolName = "stop.fill";
    public const string StoppingMacSymbolName = "stop.circle";
    public const string WindowsGlyph = "\uE71A";
    public const string ForegroundHex = "#FF453A";
    public const string BackgroundHex = "#1AFF453A";
    public const string BorderHex = "#44FF453A";
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;
    public const string ToolTip = "Stop running turn";
    public const string AccessibilityName = "Stop running turn";
    public const string StoppingAccessibilityName = "Stopping turn";
    public const string AlreadyStoppingReason = "Stop request is already in progress.";
    public const string NotRunningOrDisconnectedReason = "This thread is not currently running or its machine is disconnected.";

    public static StopTurnActionAvailability Availability(
        string? headerRunStatus,
        bool canStopTurn,
        bool isStoppingTurn)
    {
        var isVisible = NormalizeStatus(headerRunStatus) == ThreadRunStatuses.Running ||
            canStopTurn ||
            isStoppingTurn;
        var unavailableReason = isStoppingTurn
            ? AlreadyStoppingReason
            : isVisible && !canStopTurn
                ? NotRunningOrDisconnectedReason
                : null;

        return new StopTurnActionAvailability(
            isVisible,
            isVisible,
            isVisible && unavailableReason is null,
            isStoppingTurn,
            WindowsGlyph,
            unavailableReason is null ? AvailableOpacity : UnavailableOpacity,
            unavailableReason ?? ToolTip,
            isStoppingTurn ? StoppingAccessibilityName : AccessibilityName,
            unavailableReason ?? "",
            unavailableReason);
    }

    public static StopTurnActionPresentationSnapshot Resolve()
    {
        return new StopTurnActionPresentationSnapshot(
            ActiveMacSymbolName,
            StoppingMacSymbolName,
            WindowsGlyph,
            ForegroundHex,
            BackgroundHex,
            BorderHex,
            ToolTip,
            AccessibilityName);
    }

    private static string NormalizeStatus(string? status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => ThreadRunStatuses.Running,
            ThreadRunStatuses.NeedsInput => ThreadRunStatuses.NeedsInput,
            ThreadRunStatuses.Failed => ThreadRunStatuses.Failed,
            ThreadRunStatuses.Complete => ThreadRunStatuses.Complete,
            ThreadRunStatuses.Unknown => ThreadRunStatuses.Unknown,
            _ => ThreadRunStatuses.Idle
        };
    }
}
