namespace MapofAgents.Core;

public readonly record struct RuntimeDiagnosticsRailHeaderPresentationSnapshot(
    string MacSymbolName,
    string StrokeHex,
    double IconWidth,
    double IconHeight,
    double StrokeThickness,
    double EarTipSize,
    double LeftEarTipX,
    double RightEarTipX,
    double EarTipY,
    double ChestPieceSize,
    double ChestPieceX,
    double ChestPieceY,
    string AccessibilityName);

public static class RuntimeDiagnosticsRailHeaderPresentation
{
    public const string MacSymbolName = "stethoscope";
    public const string StrokeHex = "#A7B0BF";
    public const double IconWidth = 17;
    public const double IconHeight = 16;
    public const double StrokeThickness = 1.25;
    public const double EarTipSize = 1.4;
    public const double LeftEarTipX = 3;
    public const double RightEarTipX = 10.2;
    public const double EarTipY = 1.8;
    public const double ChestPieceSize = 3.4;
    public const double ChestPieceX = 11.8;
    public const double ChestPieceY = 9.1;
    public const string AccessibilityName = "Runtime Diagnostic";

    public static RuntimeDiagnosticsRailHeaderPresentationSnapshot Resolve()
    {
        return new RuntimeDiagnosticsRailHeaderPresentationSnapshot(
            MacSymbolName,
            StrokeHex,
            IconWidth,
            IconHeight,
            StrokeThickness,
            EarTipSize,
            LeftEarTipX,
            RightEarTipX,
            EarTipY,
            ChestPieceSize,
            ChestPieceX,
            ChestPieceY,
            AccessibilityName);
    }
}
