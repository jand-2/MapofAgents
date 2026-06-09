namespace MapofAgents.Core;

public readonly record struct ThreadComposerMetadataPresentationSnapshot(
    string ModelText,
    string EffortText,
    string ModelIconKind,
    string EffortIconKind,
    string IconForegroundHex,
    double IconWidth,
    double IconHeight,
    double IconStrokeThickness,
    bool ShowsModel,
    bool ShowsEffort,
    bool ShowsMetadataRow);

public static class ThreadComposerMetadataPresentation
{
    public const string ModelMacSymbolName = "cpu";
    public const string EffortMacSymbolName = "dial.medium";
    public const string ModelWindowsGlyph = "\uE950";
    public const string EffortWindowsGlyph = "\uE9D9";
    public const string ModelIconKind = "cpu";
    public const string EffortIconKind = "dialMedium";
    public const string IconForegroundHex = "#8F9BAA";
    public const double IconWidth = 12;
    public const double IconHeight = 12;
    public const double IconStrokeThickness = 1.15;

    public static ThreadComposerMetadataPresentationSnapshot Resolve(
        string? model,
        string? effort)
    {
        var modelText = model?.Trim() ?? "";
        var effortText = effort?.Trim() ?? "";
        var showsModel = !string.IsNullOrWhiteSpace(modelText);
        var showsEffort = !string.IsNullOrWhiteSpace(effortText);

        return new ThreadComposerMetadataPresentationSnapshot(
            modelText,
            effortText,
            ModelIconKind,
            EffortIconKind,
            IconForegroundHex,
            IconWidth,
            IconHeight,
            IconStrokeThickness,
            showsModel,
            showsEffort,
            showsModel || showsEffort);
    }
}
