namespace MapofAgents.Core;

public readonly record struct TranscriptLoadingRowPresentationSnapshot(
    bool IsInitialLoad,
    double Padding,
    double VerticalMargin,
    string HorizontalAlignment,
    string BackgroundHex,
    string BorderHex,
    double OuterColumnSpacing,
    double ProgressRingSize,
    double ProgressRingTopMargin,
    double ContentSpacing,
    double HeaderSpacing,
    double LabelIconFontSize,
    double TitleFontSize,
    double DetailFontSize,
    int DetailMaxLines);

public static class TranscriptLoadingRowPresentation
{
    public const double RegularPadding = 10;
    public const double CompactPadding = 8;
    public const double InitialVerticalMargin = 30;
    public const double CompactVerticalMargin = 0;
    public const string CenterAlignment = "Center";
    public const string LeadingAlignment = "Left";
    public const string RegularBackgroundHex = "#172DD4BF";
    public const string CompactBackgroundHex = "#122DD4BF";
    public const string RegularBorderHex = "#262DD4BF";
    public const string CompactBorderHex = "#202DD4BF";
    public const double OuterColumnSpacing = 8;
    public const double ProgressRingSize = 18;
    public const double ProgressRingTopMargin = 1;
    public const double ContentSpacing = 2;
    public const double HeaderSpacing = 6;
    public const double RegularLabelIconFontSize = 12;
    public const double CompactLabelIconFontSize = 11;
    public const double RegularTitleFontSize = 13;
    public const double CompactTitleFontSize = 12;
    public const double DetailFontSize = 11;
    public const int DetailMaxLines = 2;

    public static TranscriptLoadingRowPresentationSnapshot Resolve(bool hasLoadedTranscript)
    {
        var isInitialLoad = !hasLoadedTranscript;
        return new TranscriptLoadingRowPresentationSnapshot(
            isInitialLoad,
            isInitialLoad ? RegularPadding : CompactPadding,
            isInitialLoad ? InitialVerticalMargin : CompactVerticalMargin,
            isInitialLoad ? CenterAlignment : LeadingAlignment,
            isInitialLoad ? RegularBackgroundHex : CompactBackgroundHex,
            isInitialLoad ? RegularBorderHex : CompactBorderHex,
            OuterColumnSpacing,
            ProgressRingSize,
            ProgressRingTopMargin,
            ContentSpacing,
            HeaderSpacing,
            isInitialLoad ? RegularLabelIconFontSize : CompactLabelIconFontSize,
            isInitialLoad ? RegularTitleFontSize : CompactTitleFontSize,
            DetailFontSize,
            DetailMaxLines);
    }
}
