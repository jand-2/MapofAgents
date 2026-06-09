namespace MapofAgents.Core;

public readonly record struct HealthPopoverContentPresentationSnapshot(
    double SurfacePadding,
    double SurfaceSpacing,
    double HeaderSpacing,
    double HeaderIconSize,
    double HeaderIconCornerRadius,
    double HeaderIconFontSize,
    string HeaderIconBackgroundHex,
    string HeaderIconForegroundHex,
    double HeaderTextSpacing,
    double HeaderTitleFontSize,
    double HeaderSubtitleFontSize,
    string HeaderSubtitleForegroundHex,
    double CloseButtonSize,
    double CloseButtonCornerRadius,
    double CloseIconFontSize,
    double SummaryPadding,
    double SummaryCornerRadius,
    double SummaryBorderThickness,
    double SummaryStackSpacing,
    double SummaryTitleFontSize,
    double SummaryDetailFontSize,
    string SummaryBackgroundHex,
    string SummaryBorderHex,
    string SummaryTitleForegroundHex,
    string SummaryDetailForegroundHex,
    double ActionStackSpacing,
    double ActionButtonMinHeight,
    double ActionButtonCornerRadius,
    double ActionButtonHorizontalPadding,
    double ActionButtonVerticalPadding,
    string ActionButtonBackgroundHex,
    string ActionButtonBorderHex,
    string ActionButtonForegroundHex,
    double ActionContentSpacing,
    double ActionIconSize,
    double ActionTextFontSize);

public static class HealthPopoverContentPresentation
{
    public const double SurfacePadding = 12;
    public const double SurfaceSpacing = 12;
    public const double HeaderSpacing = 8;
    public const double HeaderIconSize = 26;
    public const double HeaderIconCornerRadius = 6;
    public const double HeaderIconFontSize = 13;
    public const string HeaderIconBackgroundHex = "#1A30D158";
    public const string HeaderIconForegroundHex = "#30D158";
    public const double HeaderTextSpacing = 1;
    public const double HeaderTitleFontSize = 16;
    public const double HeaderSubtitleFontSize = 12;
    public const string HeaderSubtitleForegroundHex = "#A7B0BF";
    public const double CloseButtonSize = 24;
    public const double CloseButtonCornerRadius = 12;
    public const double CloseIconFontSize = 12;
    public const double SummaryPadding = 10;
    public const double SummaryCornerRadius = 8;
    public const double SummaryBorderThickness = 1;
    public const double SummaryStackSpacing = 3;
    public const double SummaryTitleFontSize = 12;
    public const double SummaryDetailFontSize = 12;
    public const string SummaryBackgroundHex = "#1A30D158";
    public const string SummaryBorderHex = "#2630D158";
    public const string SummaryTitleForegroundHex = "#F2F4F7";
    public const string SummaryDetailForegroundHex = "#A7B0BF";
    public const double ActionStackSpacing = 8;
    public const double ActionButtonMinHeight = 28;
    public const double ActionButtonCornerRadius = 6;
    public const double ActionButtonHorizontalPadding = 8;
    public const double ActionButtonVerticalPadding = 3;
    public const string ActionButtonBackgroundHex = "#00FFFFFF";
    public const string ActionButtonBorderHex = "#00FFFFFF";
    public const string ActionButtonForegroundHex = "#D7DCE5";
    public const double ActionContentSpacing = 7;
    public const double ActionIconSize = 16;
    public const double ActionTextFontSize = 13;

    public static HealthPopoverContentPresentationSnapshot Resolve()
    {
        return new HealthPopoverContentPresentationSnapshot(
            SurfacePadding,
            SurfaceSpacing,
            HeaderSpacing,
            HeaderIconSize,
            HeaderIconCornerRadius,
            HeaderIconFontSize,
            HeaderIconBackgroundHex,
            HeaderIconForegroundHex,
            HeaderTextSpacing,
            HeaderTitleFontSize,
            HeaderSubtitleFontSize,
            HeaderSubtitleForegroundHex,
            CloseButtonSize,
            CloseButtonCornerRadius,
            CloseIconFontSize,
            SummaryPadding,
            SummaryCornerRadius,
            SummaryBorderThickness,
            SummaryStackSpacing,
            SummaryTitleFontSize,
            SummaryDetailFontSize,
            SummaryBackgroundHex,
            SummaryBorderHex,
            SummaryTitleForegroundHex,
            SummaryDetailForegroundHex,
            ActionStackSpacing,
            ActionButtonMinHeight,
            ActionButtonCornerRadius,
            ActionButtonHorizontalPadding,
            ActionButtonVerticalPadding,
            ActionButtonBackgroundHex,
            ActionButtonBorderHex,
            ActionButtonForegroundHex,
            ActionContentSpacing,
            ActionIconSize,
            ActionTextFontSize);
    }
}
