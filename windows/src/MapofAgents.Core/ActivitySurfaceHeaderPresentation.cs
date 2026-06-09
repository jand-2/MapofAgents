namespace MapofAgents.Core;

public readonly record struct ActivitySurfaceHeaderPresentationSnapshot(
    string RailMacSymbolName,
    string NotificationMacSymbolName,
    string StrokeHex,
    string BadgeHex,
    double RailIconWidth,
    double RailIconHeight,
    double RailStrokeThickness,
    double BellIconWidth,
    double BellIconHeight,
    double BellStrokeThickness,
    double BadgeSize,
    double BadgeX,
    double BadgeY,
    string RailAccessibilityName,
    string HistoryAccessibilityName,
    string PreferencesAccessibilityName);

public static class ActivitySurfaceHeaderPresentation
{
    public const string RailMacSymbolName = "waveform.path.ecg";
    public const string NotificationMacSymbolName = "bell.badge";
    public const string StrokeHex = "#A7B0BF";
    public const string BadgeHex = "#A7B0BF";
    public const double RailIconWidth = 17;
    public const double RailIconHeight = 16;
    public const double RailStrokeThickness = 1.25;
    public const double BellIconWidth = 16;
    public const double BellIconHeight = 15;
    public const double BellStrokeThickness = 1.1;
    public const double BadgeSize = 5;
    public const double BadgeX = 11;
    public const double BadgeY = 1;
    public const string RailAccessibilityName = "Workflow activity";
    public const string HistoryAccessibilityName = "Activity";
    public const string PreferencesAccessibilityName = "Notification preferences";

    public static ActivitySurfaceHeaderPresentationSnapshot Resolve()
    {
        return new ActivitySurfaceHeaderPresentationSnapshot(
            RailMacSymbolName,
            NotificationMacSymbolName,
            StrokeHex,
            BadgeHex,
            RailIconWidth,
            RailIconHeight,
            RailStrokeThickness,
            BellIconWidth,
            BellIconHeight,
            BellStrokeThickness,
            BadgeSize,
            BadgeX,
            BadgeY,
            RailAccessibilityName,
            HistoryAccessibilityName,
            PreferencesAccessibilityName);
    }
}
