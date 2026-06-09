namespace MapofAgents.Core;

public readonly record struct ThreadHeaderIdentityActionPresentationSnapshot(
    string RenameMacSymbolName,
    string SaveMacSymbolName,
    string CopyMacSymbolName,
    string RenameWindowsGlyph,
    string SaveWindowsGlyph,
    string CopyWindowsGlyph,
    string RenameForegroundHex,
    string CopyForegroundHex,
    string BackgroundHex,
    double RenameHitTargetSize,
    double RenameIconFontSize,
    double CopyHitTargetSize,
    double CopyIconFontSize,
    double BorderThickness,
    string RenameToolTip,
    string RenameAccessibilityName,
    string SaveToolTip,
    string SaveAccessibilityName,
    string CopyToolTip,
    string CopyAccessibilityName);

public static class ThreadHeaderIdentityActionPresentation
{
    public const string RenameMacSymbolName = "pencil";
    public const string SaveMacSymbolName = "checkmark";
    public const string CopyMacSymbolName = "doc.on.doc";
    public const string RenameWindowsGlyph = "\uE70F";
    public const string SaveWindowsGlyph = "\uE73E";
    public const string CopyWindowsGlyph = "\uE8C8";
    public const string RenameForegroundHex = "#A7B0BF";
    public const string CopyForegroundHex = "#8F9BAA";
    public const string BackgroundHex = "#00FFFFFF";
    public const double RenameHitTargetSize = 18;
    public const double RenameIconFontSize = 12;
    public const double CopyHitTargetSize = 18;
    public const double CopyIconFontSize = 10;
    public const double BorderThickness = 0;
    public const string RenameToolTip = "Rename";
    public const string RenameAccessibilityName = "Rename thread";
    public const string SaveToolTip = "Save thread name";
    public const string SaveAccessibilityName = "Save thread name";
    public const string CopyToolTip = "Copy thread id";
    public const string CopyAccessibilityName = "Copy thread ID";

    public static ThreadHeaderIdentityActionPresentationSnapshot Resolve()
    {
        return new ThreadHeaderIdentityActionPresentationSnapshot(
            RenameMacSymbolName,
            SaveMacSymbolName,
            CopyMacSymbolName,
            RenameWindowsGlyph,
            SaveWindowsGlyph,
            CopyWindowsGlyph,
            RenameForegroundHex,
            CopyForegroundHex,
            BackgroundHex,
            RenameHitTargetSize,
            RenameIconFontSize,
            CopyHitTargetSize,
            CopyIconFontSize,
            BorderThickness,
            RenameToolTip,
            RenameAccessibilityName,
            SaveToolTip,
            SaveAccessibilityName,
            CopyToolTip,
            CopyAccessibilityName);
    }
}
