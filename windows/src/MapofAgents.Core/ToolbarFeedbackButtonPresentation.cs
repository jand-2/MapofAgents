namespace MapofAgents.Core;

public readonly record struct ToolbarFeedbackButtonPresentationSnapshot(
    double Opacity,
    string ToolTip,
    string AccessibilityHint,
    string AccessibilityValue);

public static class ToolbarFeedbackButtonPresentation
{
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;

    public static ToolbarFeedbackButtonPresentationSnapshot Resolve(
        string? unavailableReason,
        string availableToolTip)
    {
        if (string.IsNullOrWhiteSpace(unavailableReason))
        {
            return new ToolbarFeedbackButtonPresentationSnapshot(
                AvailableOpacity,
                availableToolTip,
                string.Empty,
                string.Empty);
        }

        var reason = unavailableReason.Trim();
        return new ToolbarFeedbackButtonPresentationSnapshot(
            UnavailableOpacity,
            reason,
            reason,
            $"Unavailable: {reason}");
    }
}
