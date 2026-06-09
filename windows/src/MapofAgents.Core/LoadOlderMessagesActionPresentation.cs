namespace MapofAgents.Core;

public readonly record struct LoadOlderMessagesActionSnapshot(
    bool IsVisible,
    bool IsButtonEnabled,
    double Opacity,
    bool ShowsProgress,
    bool ShowsIdleIcon,
    string ButtonText,
    string ToolTip,
    string AccessibilityHint,
    string? UnavailableReason,
    double ButtonMinHeight,
    double ButtonHorizontalPadding,
    double ButtonVerticalPadding,
    double ContentSpacing,
    double ProgressRingSize,
    double IdleIconFontSize,
    double TextFontSize);

public static class LoadOlderMessagesActionPresentation
{
    public const string ToolTip = "Show older messages";
    public const string LoadingText = "Loading older messages";
    public const string UnavailableReason = "Older messages are already loading.";
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;
    public const bool ShowsIdleIcon = false;
    public const double ButtonMinHeight = 28;
    public const double ButtonHorizontalPadding = 7;
    public const double ButtonVerticalPadding = 3;
    public const double ContentSpacing = 6;
    public const double ProgressRingSize = 14;
    public const double IdleIconFontSize = 11;
    public const double TextFontSize = 12;

    public static LoadOlderMessagesActionSnapshot Resolve(
        bool hasOlderCursor,
        bool isLoadingOlder)
    {
        if (!hasOlderCursor)
        {
            return new LoadOlderMessagesActionSnapshot(
                false,
                false,
                AvailableOpacity,
                false,
                ShowsIdleIcon,
                ToolTip,
                ToolTip,
                "",
                null,
                ButtonMinHeight,
                ButtonHorizontalPadding,
                ButtonVerticalPadding,
                ContentSpacing,
                ProgressRingSize,
                IdleIconFontSize,
                TextFontSize);
        }

        if (isLoadingOlder)
        {
            return new LoadOlderMessagesActionSnapshot(
                true,
                true,
                UnavailableOpacity,
                true,
                ShowsIdleIcon,
                LoadingText,
                UnavailableReason,
                UnavailableReason,
                UnavailableReason,
                ButtonMinHeight,
                ButtonHorizontalPadding,
                ButtonVerticalPadding,
                ContentSpacing,
                ProgressRingSize,
                IdleIconFontSize,
                TextFontSize);
        }

        return new LoadOlderMessagesActionSnapshot(
            true,
            true,
            AvailableOpacity,
            false,
            ShowsIdleIcon,
            ToolTip,
            ToolTip,
            "",
            null,
            ButtonMinHeight,
            ButtonHorizontalPadding,
            ButtonVerticalPadding,
            ContentSpacing,
            ProgressRingSize,
            IdleIconFontSize,
            TextFontSize);
    }
}
