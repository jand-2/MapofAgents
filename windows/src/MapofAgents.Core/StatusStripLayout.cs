namespace MapofAgents.Core;

public readonly record struct StatusStripLayoutMetrics(
    double EdgeInset,
    double HorizontalPadding,
    double VerticalPadding,
    double SurfaceCornerRadius,
    double GroupSpacing,
    double IconTextSpacing,
    double DividerWidth,
    double DividerHeight,
    string DividerFillHex,
    double FontSize,
    double IconFontSize,
    double LocalConnectedIconWidth,
    double LocalConnectedIconHeight,
    double LocalConnectedCheckStrokeThickness,
    double RemoteAntennaIconWidth,
    double RemoteAntennaIconHeight,
    double RemoteAntennaStrokeThickness,
    double ErrorMaxWidth,
    int ErrorMaxLines,
    bool IsErrorTextSelectable);

public static class StatusStripLayout
{
    public const double EdgeInset = 14;
    public const double HorizontalPadding = 12;
    public const double VerticalPadding = 8;
    public const double SurfaceCornerRadius = 8;
    public const double GroupSpacing = 12;
    public const double IconTextSpacing = 6;
    public const double DividerWidth = 1;
    public const double DividerHeight = 16;
    public const string DividerFillHex = "#24FFFFFF";
    public const double FontSize = 12;
    public const double IconFontSize = 12;
    public const double LocalConnectedIconWidth = 13;
    public const double LocalConnectedIconHeight = 13;
    public const double LocalConnectedCheckStrokeThickness = 1.45;
    public const double RemoteAntennaIconWidth = 16;
    public const double RemoteAntennaIconHeight = 14;
    public const double RemoteAntennaStrokeThickness = 1.15;
    public const double ErrorMaxWidth = 420;
    public const int ErrorMaxLines = 2;
    public const bool IsErrorTextSelectable = true;

    public static StatusStripLayoutMetrics Resolve()
    {
        return new StatusStripLayoutMetrics(
            EdgeInset,
            HorizontalPadding,
            VerticalPadding,
            SurfaceCornerRadius,
            GroupSpacing,
            IconTextSpacing,
            DividerWidth,
            DividerHeight,
            DividerFillHex,
            FontSize,
            IconFontSize,
            LocalConnectedIconWidth,
            LocalConnectedIconHeight,
            LocalConnectedCheckStrokeThickness,
            RemoteAntennaIconWidth,
            RemoteAntennaIconHeight,
            RemoteAntennaStrokeThickness,
            ErrorMaxWidth,
            ErrorMaxLines,
            IsErrorTextSelectable);
    }
}
