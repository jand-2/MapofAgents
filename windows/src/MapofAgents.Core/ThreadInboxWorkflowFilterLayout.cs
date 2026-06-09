namespace MapofAgents.Core;

public readonly record struct ThreadInboxWorkflowFilterLayoutMetrics(
    double FontSize,
    double Height,
    double CornerRadius,
    double BorderThickness,
    double HorizontalPadding,
    double VerticalPadding,
    string BackgroundHex,
    string PointerOverBackgroundHex,
    string PressedBackgroundHex,
    string BorderHex,
    string FocusedBorderHex,
    string ForegroundHex,
    string ChevronForegroundHex);

public static class ThreadInboxWorkflowFilterLayout
{
    public const double CaptionFontSize = 12;
    public const double ControlHeight = 28;
    public const double CornerRadius = 6;
    public const double BorderThickness = 1;
    public const double HorizontalPadding = 8;
    public const double VerticalPadding = 3;
    public const string BackgroundHex = "#142A2C30";
    public const string PointerOverBackgroundHex = "#1F2A2C30";
    public const string PressedBackgroundHex = "#292A2C30";
    public const string BorderHex = "#24FFFFFF";
    public const string FocusedBorderHex = "#660A84FF";
    public const string ForegroundHex = "#F2F4F7";
    public const string ChevronForegroundHex = "#A7B0BF";

    public static ThreadInboxWorkflowFilterLayoutMetrics Measure()
    {
        return new ThreadInboxWorkflowFilterLayoutMetrics(
            CaptionFontSize,
            ControlHeight,
            CornerRadius,
            BorderThickness,
            HorizontalPadding,
            VerticalPadding,
            BackgroundHex,
            PointerOverBackgroundHex,
            PressedBackgroundHex,
            BorderHex,
            FocusedBorderHex,
            ForegroundHex,
            ChevronForegroundHex);
    }
}
