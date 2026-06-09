namespace MapofAgents.Core;

public readonly record struct ToolbarShellPresentationSnapshot(
    double EdgeInset,
    double Padding,
    double CornerRadius,
    double MaxWidth,
    double GroupSpacing,
    double DividerWidth,
    double DividerHeight,
    string DividerFillHex,
    string BorderHex,
    double BorderThickness);

public static class ToolbarShellPresentation
{
    public const double EdgeInset = 14;
    public const double Padding = 10;
    public const double CornerRadius = 8;
    public const double MaxWidth = 1240;
    public const double GroupSpacing = 10;
    public const double DividerWidth = 1;
    public const double DividerHeight = 20;
    public const string DividerFillHex = "#24FFFFFF";
    public const string BorderHex = "#00FFFFFF";
    public const double BorderThickness = 0;

    public static ToolbarShellPresentationSnapshot Resolve()
    {
        return new ToolbarShellPresentationSnapshot(
            EdgeInset,
            Padding,
            CornerRadius,
            MaxWidth,
            GroupSpacing,
            DividerWidth,
            DividerHeight,
            DividerFillHex,
            BorderHex,
            BorderThickness);
    }
}
