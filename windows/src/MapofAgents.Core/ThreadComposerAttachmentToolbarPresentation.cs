namespace MapofAgents.Core;

public readonly record struct ThreadComposerAttachmentToolbarPresentationSnapshot(
    string AttachMacSymbolName,
    string PasteMacSymbolName,
    string AttachWindowsGlyph,
    string PasteWindowsGlyph,
    string ForegroundHex,
    string BackgroundHex,
    double ToolbarSpacing,
    double ButtonSize,
    double IconFontSize,
    double BorderThickness,
    double CountFontSize,
    string CountForegroundHex,
    string AttachToolTip,
    string AttachAccessibilityName,
    string PasteToolTip,
    string PasteAccessibilityName);

public static class ThreadComposerAttachmentToolbarPresentation
{
    public const string AttachMacSymbolName = "paperclip";
    public const string PasteMacSymbolName = "doc.on.clipboard";
    public const string AttachWindowsGlyph = "\uE723";
    public const string PasteWindowsGlyph = "\uE77F";
    public const string ForegroundHex = "#A7B0BF";
    public const string BackgroundHex = "#00FFFFFF";
    public const double ToolbarSpacing = 8;
    public const double ButtonSize = 18;
    public const double IconFontSize = 12;
    public const double BorderThickness = 0;
    public const double CountFontSize = ThreadAttachmentFeedbackPresentation.CountFontSize;
    public const string CountForegroundHex = ThreadAttachmentFeedbackPresentation.CountForegroundHex;
    public const string AttachToolTip = "Attach files";
    public const string AttachAccessibilityName = "Attach files";
    public const string PasteToolTip = "Paste screenshot or files";
    public const string PasteAccessibilityName = "Paste screenshot or files";

    public static ThreadComposerAttachmentToolbarPresentationSnapshot Resolve()
    {
        return new ThreadComposerAttachmentToolbarPresentationSnapshot(
            AttachMacSymbolName,
            PasteMacSymbolName,
            AttachWindowsGlyph,
            PasteWindowsGlyph,
            ForegroundHex,
            BackgroundHex,
            ToolbarSpacing,
            ButtonSize,
            IconFontSize,
            BorderThickness,
            CountFontSize,
            CountForegroundHex,
            AttachToolTip,
            AttachAccessibilityName,
            PasteToolTip,
            PasteAccessibilityName);
    }
}
