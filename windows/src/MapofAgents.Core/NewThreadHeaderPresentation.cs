namespace MapofAgents.Core;

public readonly record struct NewThreadHeaderPresentationSnapshot(
    string MacSymbolName,
    string ThreadGlyph,
    string BadgeText,
    string BackgroundHex,
    string ForegroundHex,
    string BadgeBackgroundHex,
    string BadgeForegroundHex);

public static class NewThreadHeaderPresentation
{
    public const string MacSymbolName = "plus.bubble";
    public const string ThreadGlyph = "\uE8F2";
    public const string BadgeText = "+";
    public const string BackgroundHex = "#1A0A84FF";
    public const string ForegroundHex = "#0A84FF";
    public const string BadgeBackgroundHex = "#FFFFFFFF";
    public const string BadgeForegroundHex = "#0A84FF";

    public static NewThreadHeaderPresentationSnapshot Resolve()
    {
        return new NewThreadHeaderPresentationSnapshot(
            MacSymbolName,
            ThreadGlyph,
            BadgeText,
            BackgroundHex,
            ForegroundHex,
            BadgeBackgroundHex,
            BadgeForegroundHex);
    }
}
