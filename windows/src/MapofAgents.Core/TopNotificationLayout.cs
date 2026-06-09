namespace MapofAgents.Core;

public readonly record struct TopNotificationLayoutMetrics(
    double StackWidth,
    double HistoryWidth,
    double LeftInset,
    double TopInset,
    double RightInset,
    double BottomInset,
    double CardShadowTranslation,
    double HistoryShadowTranslation,
    double CardDismissButtonSize,
    double CardDismissIconFontSize);

public static class TopNotificationLayout
{
    public const double StackWidth = 360;
    public const double HistoryWidth = 380;
    public const double EdgeInset = 14;
    public const double CardShadowTranslation = 18;
    public const double HistoryShadowTranslation = 18;
    public const double CardDismissButtonSize = 18;
    public const double CardDismissIconFontSize = 11;

    public static TopNotificationLayoutMetrics Measure()
    {
        return new TopNotificationLayoutMetrics(
            StackWidth,
            HistoryWidth,
            0,
            EdgeInset,
            EdgeInset,
            0,
            CardShadowTranslation,
            HistoryShadowTranslation,
            CardDismissButtonSize,
            CardDismissIconFontSize);
    }
}
