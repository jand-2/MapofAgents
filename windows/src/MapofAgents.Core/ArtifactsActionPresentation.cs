namespace MapofAgents.Core;

public readonly record struct ArtifactsActionPresentationSnapshot(
    string MacSymbolName,
    string ActionForegroundHex,
    string HeaderForegroundHex,
    string EmptyForegroundHex,
    double HitTargetSize,
    double ActionIconSize,
    double HeaderIconSize,
    double EmptyIconSize,
    double StrokeThickness,
    string ShippingBoxPathData,
    string UnavailableReason,
    double UnavailableOpacity,
    string ToolTip,
    string AccessibilityName);

public static class ArtifactsActionPresentation
{
    public const string MacSymbolName = "shippingbox";
    public const string ActionForegroundHex = "#A7B0BF";
    public const string HeaderForegroundHex = "#6AB7FF";
    public const string EmptyForegroundHex = "#697586";
    public const double HitTargetSize = 24;
    public const double ActionIconSize = 16;
    public const double HeaderIconSize = 16;
    public const double EmptyIconSize = 30;
    public const double StrokeThickness = 1.25;
    public const double UnavailableOpacity = 0.48;
    public const string ShippingBoxPathData =
        "M2.2,5.1 L8,2.3 L13.8,5.1 L13.8,12.2 L8,14.9 L2.2,12.2 Z M2.2,5.1 L8,7.9 L13.8,5.1 M8,7.9 L8,14.9 M5,3.7 L10.8,6.5";
    public const string UnavailableReason = "This thread has not produced any artifacts yet.";
    public const string ToolTip = "Artifacts";
    public const string AccessibilityName = "Artifacts";

    public static ArtifactsActionPresentationSnapshot Resolve()
    {
        return new ArtifactsActionPresentationSnapshot(
            MacSymbolName,
            ActionForegroundHex,
            HeaderForegroundHex,
            EmptyForegroundHex,
            HitTargetSize,
            ActionIconSize,
            HeaderIconSize,
            EmptyIconSize,
            StrokeThickness,
            ShippingBoxPathData,
            UnavailableReason,
            UnavailableOpacity,
            ToolTip,
            AccessibilityName);
    }
}
