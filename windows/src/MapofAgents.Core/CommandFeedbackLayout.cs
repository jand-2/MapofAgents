namespace MapofAgents.Core;

public readonly record struct CommandFeedbackLayoutMetrics(
    double Width,
    double LeftInset,
    double TopInset,
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double BorderThickness,
    double TextFontSize,
    double TextLineHeight,
    int TextMaxLines,
    double ShadowTranslationZ);

public static class CommandFeedbackLayout
{
    public const double Width = 240;
    public const double EdgeInset = 14;
    public const double TopInset = 76;
    public const double ControlTopOffset = 42;
    public const double ControlBottomGap = 8;
    public const double HorizontalPadding = 10;
    public const double VerticalPadding = 7;
    public const double CornerRadius = 8;
    public const double BorderThickness = 1;
    public const double TextFontSize = 12;
    public const double TextLineHeight = 16;
    public const int TextMaxLines = 3;
    public const double ShadowTranslationZ = 18;

    public static CommandFeedbackLayoutMetrics Measure()
    {
        return new CommandFeedbackLayoutMetrics(
            Width,
            EdgeInset,
            TopInset,
            HorizontalPadding,
            VerticalPadding,
            CornerRadius,
            BorderThickness,
            TextFontSize,
            TextLineHeight,
            TextMaxLines,
            ShadowTranslationZ);
    }

    public static CommandFeedbackLayoutMetrics MeasureAnchored(
        double anchorLeft,
        double anchorTop,
        double anchorWidth,
        double anchorHeight,
        double rootWidth)
    {
        var preferredLeft = anchorLeft + anchorWidth / 2 - Width / 2;
        var maxLeft = rootWidth > 0
            ? Math.Max(EdgeInset, rootWidth - Width - EdgeInset)
            : preferredLeft;
        var left = rootWidth > 0
            ? Math.Clamp(preferredLeft, EdgeInset, maxLeft)
            : Math.Max(EdgeInset, preferredLeft);
        var preferredTop = anchorTop - ControlTopOffset;
        var top = preferredTop >= EdgeInset
            ? preferredTop
            : anchorTop + Math.Max(0, anchorHeight) + ControlBottomGap;

        return new CommandFeedbackLayoutMetrics(
            Width,
            left,
            top,
            HorizontalPadding,
            VerticalPadding,
            CornerRadius,
            BorderThickness,
            TextFontSize,
            TextLineHeight,
            TextMaxLines,
            ShadowTranslationZ);
    }
}
