namespace MapofAgents.Core;

public readonly record struct ThreadInboxModePickerPresentationSnapshot(
    string[] PrimaryModeKeys,
    string[] SecondaryModeKeys,
    bool ShowsSecondaryOverflow,
    string OverflowMacSymbolName,
    string OverflowToolTip,
    double PrimaryButtonSpacing,
    double PrimaryButtonHeight,
    double PrimaryButtonCornerRadius,
    double PrimaryButtonBorderThickness,
    double PrimaryButtonHorizontalPadding,
    double PrimaryButtonVerticalPadding,
    double PrimaryButtonFontSize,
    string OverflowFillHex,
    double OverflowIconWidth,
    double OverflowIconHeight,
    double OverflowDotSize,
    double OverflowDotSpacing);

public static class ThreadInboxModePickerPresentation
{
    public const string ActiveMode = "active";
    public const string FinishedMode = "finished";
    public const string NeedsYouMode = "needsYou";
    public const string UnreadMode = "unread";
    public const string RecentMode = "recent";
    public const string ArchivedMode = "archived";
    public const string OverflowMacSymbolName = "ellipsis";
    public const string OverflowToolTip = "More inbox views";
    public const string SelectedFillHex = "#6AB7FF";
    public const string InactiveFillHex = "#A7B0BF";
    public const string SelectedBackgroundHex = "#180A84FF";
    public const string InactiveBackgroundHex = "#00FFFFFF";
    public const string SelectedBorderHex = "#440A84FF";
    public const string InactiveBorderHex = "#24FFFFFF";
    public const double PrimaryButtonSpacing = 4;
    public const double PrimaryButtonHeight = 24;
    public const double PrimaryButtonCornerRadius = 6;
    public const double PrimaryButtonBorderThickness = 1;
    public const double PrimaryButtonHorizontalPadding = 0;
    public const double PrimaryButtonVerticalPadding = 2;
    public const double PrimaryButtonFontSize = 11;
    public const double OverflowIconWidth = 15;
    public const double OverflowIconHeight = 15;
    public const double OverflowDotSize = 2.2;
    public const double OverflowDotSpacing = 2.2;

    public static ThreadInboxModePickerPresentationSnapshot Resolve(bool isSecondaryModeSelected)
    {
        return new ThreadInboxModePickerPresentationSnapshot(
            [ActiveMode, FinishedMode],
            [NeedsYouMode, UnreadMode, RecentMode, ArchivedMode],
            false,
            OverflowMacSymbolName,
            OverflowToolTip,
            PrimaryButtonSpacing,
            PrimaryButtonHeight,
            PrimaryButtonCornerRadius,
            PrimaryButtonBorderThickness,
            PrimaryButtonHorizontalPadding,
            PrimaryButtonVerticalPadding,
            PrimaryButtonFontSize,
            isSecondaryModeSelected ? SelectedFillHex : InactiveFillHex,
            OverflowIconWidth,
            OverflowIconHeight,
            OverflowDotSize,
            OverflowDotSpacing);
    }
}
