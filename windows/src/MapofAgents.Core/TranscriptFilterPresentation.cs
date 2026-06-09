namespace MapofAgents.Core;

public readonly record struct TranscriptFilterPresentationSnapshot(
    string MacSymbolName,
    string ForegroundHex,
    string MutedForegroundHex,
    double BarHorizontalPadding,
    double BarVerticalPadding,
    double BarColumnSpacing,
    double ButtonHorizontalPadding,
    double ButtonVerticalPadding,
    double ButtonCornerRadius,
    double ButtonContentSpacing,
    double SummaryFontSize,
    double DetailFontSize,
    double ResetButtonSize,
    double ResetIconFontSize,
    double IconSize,
    double EmptyIconSize,
    double StrokeThickness,
    double CircleInset,
    double TopLineWidth,
    double MiddleLineWidth,
    double BottomLineWidth,
    string ToolTip,
    string AccessibilityName);

public static class TranscriptFilterPresentation
{
    public const string MacSymbolName = "line.3.horizontal.decrease.circle";
    public const string ForegroundHex = "#A7B0BF";
    public const string MutedForegroundHex = "#697586";
    public const double BarHorizontalPadding = 14;
    public const double BarVerticalPadding = 7;
    public const double BarColumnSpacing = 8;
    public const double ButtonHorizontalPadding = 7;
    public const double ButtonVerticalPadding = 3;
    public const double ButtonCornerRadius = 5;
    public const double ButtonContentSpacing = 6;
    public const double SummaryFontSize = 12;
    public const double DetailFontSize = 11;
    public const double ResetButtonSize = 18;
    public const double ResetIconFontSize = 11;
    public const double IconSize = 16;
    public const double EmptyIconSize = 30;
    public const double StrokeThickness = 1.25;
    public const double CircleInset = 1.4;
    public const double TopLineWidth = 8;
    public const double MiddleLineWidth = 6;
    public const double BottomLineWidth = 4;
    public const string ToolTip = "Filter transcript rows";
    public const string AccessibilityName = "Filter transcript rows";

    public static TranscriptFilterPresentationSnapshot Resolve()
    {
        return new TranscriptFilterPresentationSnapshot(
            MacSymbolName,
            ForegroundHex,
            MutedForegroundHex,
            BarHorizontalPadding,
            BarVerticalPadding,
            BarColumnSpacing,
            ButtonHorizontalPadding,
            ButtonVerticalPadding,
            ButtonCornerRadius,
            ButtonContentSpacing,
            SummaryFontSize,
            DetailFontSize,
            ResetButtonSize,
            ResetIconFontSize,
            IconSize,
            EmptyIconSize,
            StrokeThickness,
            CircleInset,
            TopLineWidth,
            MiddleLineWidth,
            BottomLineWidth,
            ToolTip,
            AccessibilityName);
    }

    public static string DetailForegroundHex(bool isShowingAllRows)
    {
        return isShowingAllRows ? MutedForegroundHex : ForegroundHex;
    }
}
