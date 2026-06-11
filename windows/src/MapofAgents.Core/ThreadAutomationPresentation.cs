namespace MapofAgents.Core;

public readonly record struct ThreadAutomationPresentationSnapshot(
    bool IsVisible,
    bool IsActive,
    string WindowsGlyph,
    string MacSymbolName,
    string ForegroundHex,
    string BackgroundHex,
    string ToolTip,
    string AccessibilityName,
    string AccessibilityValue,
    double HitTargetSize,
    double IconFontSize,
    double BorderThickness);

public readonly record struct ThreadAutomationWebConfig(
    string Glyph,
    string ActiveForegroundHex,
    string InactiveForegroundHex,
    string ActiveBackgroundHex,
    double HitTargetSize,
    double IconFontSize);

public static class ThreadAutomationPresentation
{
    public const string WindowsGlyph = "\uE823";
    public const string ActiveMacSymbolName = "alarm.fill";
    public const string InactiveMacSymbolName = "alarm";
    public const string ActiveForegroundHex = "#FF9F0A";
    public const string InactiveForegroundHex = "#A7B0BF";
    public const string ActiveBackgroundHex = "#1CFF9F0A";
    public const string InactiveBackgroundHex = "#00FFFFFF";
    public const string HiddenToolTip = "No automation is linked to this thread";
    public const string AccessibilityName = "Thread automation";
    public const double HitTargetSize = 24;
    public const double NodeHitTargetSize = 18;
    public const double IconFontSize = 12;
    public const double BorderThickness = 0;

    public static ThreadAutomationPresentationSnapshot Resolve(CodexAutomationSummary? automation)
    {
        if (automation is null)
        {
            return new ThreadAutomationPresentationSnapshot(
                false,
                false,
                WindowsGlyph,
                InactiveMacSymbolName,
                InactiveForegroundHex,
                InactiveBackgroundHex,
                HiddenToolTip,
                AccessibilityName,
                HiddenToolTip,
                HitTargetSize,
                IconFontSize,
                BorderThickness);
        }

        var state = automation.IsActive ? "active" : "paused";
        var help = $"{automation.Name} automation is {state}";
        return new ThreadAutomationPresentationSnapshot(
            true,
            automation.IsActive,
            WindowsGlyph,
            automation.IsActive ? ActiveMacSymbolName : InactiveMacSymbolName,
            automation.IsActive ? ActiveForegroundHex : InactiveForegroundHex,
            automation.IsActive ? ActiveBackgroundHex : InactiveBackgroundHex,
            help,
            AccessibilityName,
            help,
            HitTargetSize,
            IconFontSize,
            BorderThickness);
    }

    public static ThreadAutomationWebConfig WebConfig()
    {
        return new ThreadAutomationWebConfig(
            WindowsGlyph,
            ActiveForegroundHex,
            InactiveForegroundHex,
            ActiveBackgroundHex,
            NodeHitTargetSize,
            IconFontSize);
    }
}
