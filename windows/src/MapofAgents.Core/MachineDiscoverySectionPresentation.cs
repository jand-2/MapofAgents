namespace MapofAgents.Core;

public readonly record struct MachineDiscoverySectionPresentationSnapshot(
    double SectionSpacing,
    double HeaderColumnSpacing,
    double HeaderIconWidth,
    double HeaderIconFontSize,
    double HeaderTitleFontSize,
    double CollapseButtonSize,
    double CollapseIconFontSize,
    double ContentSpacing,
    double CountFontSize,
    double MessageFontSize,
    double MessageHorizontalPadding,
    double MessageVerticalPadding,
    double ListMaxHeight,
    double RowBottomGap,
    double RowHorizontalPadding,
    double RowVerticalPadding,
    double RowColumnSpacing,
    double RowIconWidth,
    double RowIconFontSize,
    double RowTitleFontSize,
    double RowDetailFontSize,
    double BadgeHorizontalPadding,
    double BadgeVerticalPadding,
    double BadgeFontSize,
    double ActionButtonSize,
    double DiagnosticLeftPadding,
    double DiagnosticBottomGap,
    double DiagnosticColumnSpacing,
    double DiagnosticIconWidth,
    double DiagnosticIconFontSize,
    double DiagnosticStackSpacing,
    double DiagnosticTitleFontSize,
    double DiagnosticDetailFontSize,
    double DiagnosticActionHorizontalPadding,
    double DiagnosticActionVerticalPadding,
    double DiagnosticActionIconFontSize,
    string CountText,
    bool ShowsCount,
    bool ShowsMessage);

public static class MachineDiscoverySectionPresentation
{
    public const double SectionSpacing = 7;
    public const double HeaderColumnSpacing = 6;
    public const double HeaderIconWidth = 16;
    public const double HeaderIconFontSize = 13;
    public const double HeaderTitleFontSize = 12;
    public const double CollapseButtonSize = 18;
    public const double CollapseIconFontSize = 10;
    public const double ContentSpacing = 7;
    public const double CountFontSize = 11;
    public const double MessageFontSize = 11;
    public const double MessageHorizontalPadding = 8;
    public const double MessageVerticalPadding = 6;
    public const double ListMaxHeight = 260;
    public const double RowBottomGap = 7;
    public const double RowHorizontalPadding = 8;
    public const double RowVerticalPadding = 6;
    public const double RowColumnSpacing = 8;
    public const double RowIconWidth = 16;
    public const double RowIconFontSize = 13;
    public const double RowTitleFontSize = 12;
    public const double RowDetailFontSize = 11;
    public const double BadgeHorizontalPadding = 5;
    public const double BadgeVerticalPadding = 2;
    public const double BadgeFontSize = 11;
    public const double ActionButtonSize = 22;
    public const double DiagnosticLeftPadding = 24;
    public const double DiagnosticBottomGap = 4;
    public const double DiagnosticColumnSpacing = 6;
    public const double DiagnosticIconWidth = 14;
    public const double DiagnosticIconFontSize = 11;
    public const double DiagnosticStackSpacing = 1;
    public const double DiagnosticTitleFontSize = 11;
    public const double DiagnosticDetailFontSize = 11;
    public const double DiagnosticActionHorizontalPadding = 6;
    public const double DiagnosticActionVerticalPadding = 2;
    public const double DiagnosticActionIconFontSize = 11;

    public static MachineDiscoverySectionPresentationSnapshot Resolve(
        int itemCount,
        bool isDiscovering,
        string singularNoun,
        string pluralNoun,
        string? message)
    {
        var hasItems = itemCount > 0;
        var countText = $"{itemCount} {(itemCount == 1 ? singularNoun : pluralNoun)}";
        return new MachineDiscoverySectionPresentationSnapshot(
            SectionSpacing,
            HeaderColumnSpacing,
            HeaderIconWidth,
            HeaderIconFontSize,
            HeaderTitleFontSize,
            CollapseButtonSize,
            CollapseIconFontSize,
            ContentSpacing,
            CountFontSize,
            MessageFontSize,
            MessageHorizontalPadding,
            MessageVerticalPadding,
            ListMaxHeight,
            RowBottomGap,
            RowHorizontalPadding,
            RowVerticalPadding,
            RowColumnSpacing,
            RowIconWidth,
            RowIconFontSize,
            RowTitleFontSize,
            RowDetailFontSize,
            BadgeHorizontalPadding,
            BadgeVerticalPadding,
            BadgeFontSize,
            ActionButtonSize,
            DiagnosticLeftPadding,
            DiagnosticBottomGap,
            DiagnosticColumnSpacing,
            DiagnosticIconWidth,
            DiagnosticIconFontSize,
            DiagnosticStackSpacing,
            DiagnosticTitleFontSize,
            DiagnosticDetailFontSize,
            DiagnosticActionHorizontalPadding,
            DiagnosticActionVerticalPadding,
            DiagnosticActionIconFontSize,
            countText,
            hasItems,
            !hasItems && !isDiscovering && !string.IsNullOrWhiteSpace(message));
    }
}
