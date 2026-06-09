namespace MapofAgents.Core;

public readonly record struct SelectionInspectorLayoutMetrics(
    double Width,
    double TopInset,
    double RightInset,
    double Padding,
    double CornerRadius,
    double HeaderSpacing,
    double ContentSpacing,
    double IconSize,
    double IconCornerRadius,
    double ShadowTranslationZ);

public static class SelectionInspectorLayout
{
    public const double NodeWidth = 310;
    public const double EdgeWidth = 300;
    public const double TopInset = 86;
    public const double RightInset = 14;
    public const double Padding = 12;
    public const double CornerRadius = 8;
    public const double HeaderSpacing = 8;
    public const double ContentSpacing = 10;
    public const double IconSize = 22;
    public const double IconCornerRadius = 6;
    public const double ShadowTranslationZ = 18;

    public static SelectionInspectorLayoutMetrics ForNode()
    {
        return Create(NodeWidth);
    }

    public static SelectionInspectorLayoutMetrics ForEdge()
    {
        return Create(EdgeWidth);
    }

    private static SelectionInspectorLayoutMetrics Create(double width)
    {
        return new SelectionInspectorLayoutMetrics(
            width,
            TopInset,
            RightInset,
            Padding,
            CornerRadius,
            HeaderSpacing,
            ContentSpacing,
            IconSize,
            IconCornerRadius,
            ShadowTranslationZ);
    }
}
