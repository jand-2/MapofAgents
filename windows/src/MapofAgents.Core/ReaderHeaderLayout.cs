namespace MapofAgents.Core;

public readonly record struct ReaderHeaderLayoutMetrics(
    double HorizontalPadding,
    double VerticalPadding,
    double RightPadding,
    double HeaderSpacing,
    double TitleFontSize,
    string TitleFontWeightName,
    bool ShowsSummary,
    bool ShowsAddLabel,
    double CandidateWidth,
    bool UsesIconOnlyClearButton,
    double ClearButtonWidth,
    double ClearButtonHeight,
    double ClearButtonHorizontalPadding,
    double ClearButtonVerticalPadding,
    string? ClearButtonToolTip);

public static class ReaderHeaderLayout
{
    public const double HorizontalPadding = 14;
    public const double VerticalPadding = 12;
    public const double HeaderSpacing = 10;
    public const double TitleFontSize = OperationalRailHeaderTypography.TitleFontSize;
    public const string TitleFontWeightName = OperationalRailHeaderTypography.TitleFontWeightName;
    public const double DesktopTitleControlReserve = 154;
    public const double CompactTitleControlReserve = 92;
    public const double TitleControlReserveBreakpoint = 860;
    public const double CompactBreakpoint = 980;
    public const double NarrowBreakpoint = 760;
    public const double VeryNarrowBreakpoint = 640;
    public const double CandidateWidth = 260;
    public const double CompactCandidateWidth = 210;
    public const double VeryNarrowCandidateWidth = 156;
    public const double ClearButtonSize = 24;
    public const double ClearButtonHorizontalPadding = 8;
    public const double ClearButtonVerticalPadding = 3;
    public const string IconOnlyClearToolTip = "Clear reader";

    public static ReaderHeaderLayoutMetrics Measure(double viewportWidth)
    {
        var width = Math.Max(0, viewportWidth);
        var compact = width < CompactBreakpoint;
        var narrow = width < NarrowBreakpoint;
        var veryNarrow = width < VeryNarrowBreakpoint;

        return new ReaderHeaderLayoutMetrics(
            HorizontalPadding,
            VerticalPadding,
            width < TitleControlReserveBreakpoint ? CompactTitleControlReserve : DesktopTitleControlReserve,
            HeaderSpacing,
            TitleFontSize,
            TitleFontWeightName,
            ShowsSummary: !narrow,
            ShowsAddLabel: !compact,
            veryNarrow ? VeryNarrowCandidateWidth : compact ? CompactCandidateWidth : CandidateWidth,
            UsesIconOnlyClearButton: narrow,
            ClearButtonSize,
            ClearButtonSize,
            narrow ? 0 : ClearButtonHorizontalPadding,
            narrow ? 0 : ClearButtonVerticalPadding,
            narrow ? IconOnlyClearToolTip : null);
    }
}
