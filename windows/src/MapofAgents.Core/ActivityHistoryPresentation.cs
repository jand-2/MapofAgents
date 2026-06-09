namespace MapofAgents.Core;

public readonly record struct ActivityHistoryPresentationSnapshot(
    double Width,
    double MaxListHeight,
    string HeaderMacFontStyleName,
    double SurfaceSpacing,
    double HeaderTitleFontSize,
    double HeaderIconSpacing,
    double HeaderActionSpacing,
    double DismissCurrentFontSize,
    double CloseButtonSize,
    double CloseIconFontSize,
    double EmptyFontSize,
    double EmptyVerticalPadding,
    double RowSpacing,
    double RowBottomGap,
    double RowPadding,
    double RowColumnSpacing,
    double RowIconColumnWidth,
    double RowIconFontSize,
    double RowContentSpacing,
    double RowTitleTimeSpacing,
    double RowTitleFontSize,
    double RowTimeFontSize,
    double RowMessageFontSize,
    double RowActionFontSize,
    double RowBorderThickness,
    bool ShowsNotificationPreferencesButton,
    string EmptyMessage,
    string DismissCurrentLabel);

public static class ActivityHistoryPresentation
{
    public const double Width = 380;
    public const double MaxListHeight = 420;
    public const string HeaderMacFontStyleName = "headline";
    public const double SurfaceSpacing = 10;
    public const double HeaderTitleFontSize = 13;
    public const double HeaderIconSpacing = 8;
    public const double HeaderActionSpacing = 8;
    public const double DismissCurrentFontSize = 12;
    public const double CloseButtonSize = 22;
    public const double CloseIconFontSize = 12;
    public const double EmptyFontSize = 12;
    public const double EmptyVerticalPadding = 10;
    public const double RowSpacing = 8;
    public const double RowBottomGap = 8;
    public const double RowPadding = 8;
    public const double RowColumnSpacing = 9;
    public const double RowIconColumnWidth = 16;
    public const double RowIconFontSize = 13;
    public const double RowContentSpacing = 3;
    public const double RowTitleTimeSpacing = 6;
    public const double RowTitleFontSize = 12;
    public const double RowTimeFontSize = 11;
    public const double RowMessageFontSize = 12;
    public const double RowActionFontSize = 11;
    public const double RowBorderThickness = 0;
    public const bool ShowsNotificationPreferencesButton = false;
    public const string EmptyMessage = "No notifications yet.";
    public const string DismissCurrentLabel = "Dismiss Current";

    public static ActivityHistoryPresentationSnapshot Resolve()
    {
        return new ActivityHistoryPresentationSnapshot(
            Width,
            MaxListHeight,
            HeaderMacFontStyleName,
            SurfaceSpacing,
            HeaderTitleFontSize,
            HeaderIconSpacing,
            HeaderActionSpacing,
            DismissCurrentFontSize,
            CloseButtonSize,
            CloseIconFontSize,
            EmptyFontSize,
            EmptyVerticalPadding,
            RowSpacing,
            RowBottomGap,
            RowPadding,
            RowColumnSpacing,
            RowIconColumnWidth,
            RowIconFontSize,
            RowContentSpacing,
            RowTitleTimeSpacing,
            RowTitleFontSize,
            RowTimeFontSize,
            RowMessageFontSize,
            RowActionFontSize,
            RowBorderThickness,
            ShowsNotificationPreferencesButton,
            EmptyMessage,
            DismissCurrentLabel);
    }
}
