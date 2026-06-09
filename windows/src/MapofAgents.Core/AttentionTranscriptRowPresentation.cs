namespace MapofAgents.Core;

public readonly record struct AttentionTranscriptRowPresentationSnapshot(
    string CategoryLabel,
    string CategoryMacSymbolName,
    string CategoryWindowsGlyph,
    string BadgeForegroundHex,
    string BadgeBackgroundHex,
    string RowBackgroundHex,
    string RowBorderHex,
    double RowBorderThickness,
    string FocusToolTip,
    string FocusAccessibilityName);

public static class AttentionTranscriptRowPresentation
{
    public const string FocusToolTip = "Open owning thread";
    public const string FocusAccessibilityName = "Open owning thread";

    public static AttentionTranscriptRowPresentationSnapshot Resolve()
    {
        var category = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyApprovals);
        var card = AttentionRequestCardPresentation.Resolve("attention", "response");

        return new AttentionTranscriptRowPresentationSnapshot(
            category.CompactTitle,
            category.MacSymbolName,
            category.WindowsGlyph,
            category.ForegroundHex,
            category.BadgeBackgroundHex,
            card.BackgroundHex,
            card.BorderHex,
            card.BorderThickness,
            FocusToolTip,
            FocusAccessibilityName);
    }
}
