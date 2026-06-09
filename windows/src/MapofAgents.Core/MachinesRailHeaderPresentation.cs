namespace MapofAgents.Core;

public readonly record struct MachinesRailHeaderPresentationSnapshot(
    string MacSymbolName,
    string StrokeHex,
    double IconWidth,
    double IconHeight,
    double UnitX,
    double UnitTopInset,
    double UnitWidth,
    double UnitHeight,
    double UnitGap,
    double StrokeThickness,
    double IndicatorSize,
    double IndicatorInsetX,
    string AccessibilityName);

public static class MachinesRailHeaderPresentation
{
    public const string MacSymbolName = "server.rack";
    public const string StrokeHex = "#A7B0BF";
    public const double IconWidth = 17;
    public const double IconHeight = 16;
    public const double UnitX = 2.5;
    public const double UnitTopInset = 1.7;
    public const double UnitWidth = 12;
    public const double UnitHeight = 3.6;
    public const double UnitGap = 1.2;
    public const double StrokeThickness = 1.2;
    public const double IndicatorSize = 1.15;
    public const double IndicatorInsetX = 1.75;
    public const string AccessibilityName = "Machines";

    public static MachinesRailHeaderPresentationSnapshot Resolve()
    {
        return new MachinesRailHeaderPresentationSnapshot(
            MacSymbolName,
            StrokeHex,
            IconWidth,
            IconHeight,
            UnitX,
            UnitTopInset,
            UnitWidth,
            UnitHeight,
            UnitGap,
            StrokeThickness,
            IndicatorSize,
            IndicatorInsetX,
            AccessibilityName);
    }
}
