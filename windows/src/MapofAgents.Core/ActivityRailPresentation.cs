namespace MapofAgents.Core;

public readonly record struct ActivityRailPresentationSnapshot(
    double Width,
    double Padding,
    double MaxHeight,
    double SurfaceSpacing,
    double ContentSpacing,
    double CountFontSize,
    double EmptyFontSize,
    double EmptyVerticalPadding,
    double ListMaxHeight,
    double RowSpacing,
    double RowHorizontalPadding,
    double RowVerticalPadding,
    double RowColumnSpacing,
    double RowIconColumnWidth,
    double RowIconFontSize,
    double RowContentSpacing,
    double RowTitleFontSize,
    double RowDetailFontSize,
    int RowDetailMaxLines,
    string EmptyMessage);

public static class ActivityRailPresentation
{
    public const double Width = 320;
    public const double Padding = 12;
    public static readonly double MaxHeight = double.PositiveInfinity;
    public const double SurfaceSpacing = 10;
    public const double ContentSpacing = 10;
    public const double CountFontSize = 11;
    public const double EmptyFontSize = 12;
    public const double EmptyVerticalPadding = 8;
    public const double ListMaxHeight = 260;
    public const double RowSpacing = 4;
    public const double RowHorizontalPadding = 8;
    public const double RowVerticalPadding = 6;
    public const double RowColumnSpacing = 8;
    public const double RowIconColumnWidth = 16;
    public const double RowIconFontSize = 13;
    public const double RowContentSpacing = 2;
    public const double RowTitleFontSize = 12;
    public const double RowDetailFontSize = 11;
    public const int RowDetailMaxLines = 2;
    public const string EmptyMessage = "No workflow activity yet.";

    public static ActivityRailPresentationSnapshot Resolve()
    {
        return new ActivityRailPresentationSnapshot(
            Width,
            Padding,
            MaxHeight,
            SurfaceSpacing,
            ContentSpacing,
            CountFontSize,
            EmptyFontSize,
            EmptyVerticalPadding,
            ListMaxHeight,
            RowSpacing,
            RowHorizontalPadding,
            RowVerticalPadding,
            RowColumnSpacing,
            RowIconColumnWidth,
            RowIconFontSize,
            RowContentSpacing,
            RowTitleFontSize,
            RowDetailFontSize,
            RowDetailMaxLines,
            EmptyMessage);
    }
}
