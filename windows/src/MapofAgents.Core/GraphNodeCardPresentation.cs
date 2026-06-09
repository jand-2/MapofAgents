namespace MapofAgents.Core;

public readonly record struct GraphNodeCardPresentationSnapshot(
    double SurfaceCornerRadius,
    double BorderWidth,
    double SelectedBorderWidth,
    double SelectedInnerStrokeWidth,
    double HighlightCornerRadius,
    double HighlightInset,
    double HighlightBorderWidth,
    double HighlightShadowRadius,
    double ShadowYOffset,
    double DefaultShadowRadius,
    double HoverShadowRadius,
    double EmphasisShadowRadius,
    double InnerPadding,
    double InnerGap,
    double HeadingGap,
    double ActionGap,
    double IconSize,
    double IconCornerRadius,
    double IconFontSize,
    double TitleRowGap,
    double TitleFontSize,
    double SubtitleTopMargin,
    double SubtitleFontSize,
    double AgentBadgeHeight,
    double AgentBadgeHorizontalPadding,
    double AgentBadgeFontSize,
    double UnreadDotSize,
    double FooterGap,
    double FooterMinHeight,
    bool FooterSpacerBeforeMetadata,
    double PillHeight,
    double PillHorizontalPadding,
    double PillFontSize,
    double PillLineHeight,
    double PillIconFontSize,
    double PillSvgIconSize);

public readonly record struct GraphNodeCardMaterialSnapshot(
    string CanvasBackgroundHex,
    string PrimaryTextHex,
    string SecondaryTextHex,
    string TertiaryTextHex,
    string SurfaceCss,
    string StrongSurfaceCss,
    string StrokeCss,
    string SoftStrokeCss,
    string DefaultShadowCss);

public static class GraphNodeCardPresentation
{
    public const string CanvasBackgroundHex = "#1D1E20";
    public const string PrimaryTextHex = "#F2F4F7";
    public const string SecondaryTextHex = "#A7B0BF";
    public const string TertiaryTextHex = "#8F9BAA";
    public const string SurfaceHex = "#212225";
    public const string StrokeHex = "#FFFFFF";
    public const string ShadowHex = "#000000";
    public const double SurfaceOpacity = 0.80;
    public const double StrongSurfaceOpacity = 0.93;
    public const double StrokeOpacity = 0.18;
    public const double SoftStrokeOpacity = 0.10;
    public const double DefaultShadowOpacity = 0.08;
    public const double SurfaceCornerRadius = 8;
    public const double BorderWidth = 2;
    public const double SelectedBorderWidth = 3;
    public const double SelectedInnerStrokeWidth = 0;
    public const double HighlightCornerRadius = 10;
    public const double HighlightInset = -5;
    public const double HighlightBorderWidth = 4;
    public const double HighlightShadowRadius = 10;
    public const double ShadowYOffset = 4;
    public const double DefaultShadowRadius = 6;
    public const double HoverShadowRadius = 8;
    public const double EmphasisShadowRadius = 12;
    public const double InnerPadding = 12;
    public const double InnerGap = 10;
    public const double HeadingGap = 9;
    public const double ActionGap = 9;
    public const double IconSize = 24;
    public const double IconCornerRadius = 6;
    public const double IconFontSize = 16;
    public const double TitleRowGap = 6;
    public const double TitleFontSize = 14;
    public const double SubtitleTopMargin = 3;
    public const double SubtitleFontSize = 12;
    public const double AgentBadgeHeight = 18;
    public const double AgentBadgeHorizontalPadding = 6;
    public const double AgentBadgeFontSize = 10;
    public const double UnreadDotSize = 7;
    public const double FooterGap = 6;
    public const double FooterMinHeight = 20;
    public const bool FooterSpacerBeforeMetadata = true;
    public const double PillHeight = 20;
    public const double PillHorizontalPadding = 7;
    public const double PillFontSize = 11;
    public const double PillLineHeight = 13;
    public const double PillIconFontSize = 8;
    public const double PillSvgIconSize = 11;

    public static GraphNodeCardPresentationSnapshot Resolve()
    {
        return new GraphNodeCardPresentationSnapshot(
            SurfaceCornerRadius,
            BorderWidth,
            SelectedBorderWidth,
            SelectedInnerStrokeWidth,
            HighlightCornerRadius,
            HighlightInset,
            HighlightBorderWidth,
            HighlightShadowRadius,
            ShadowYOffset,
            DefaultShadowRadius,
            HoverShadowRadius,
            EmphasisShadowRadius,
            InnerPadding,
            InnerGap,
            HeadingGap,
            ActionGap,
            IconSize,
            IconCornerRadius,
            IconFontSize,
            TitleRowGap,
            TitleFontSize,
            SubtitleTopMargin,
            SubtitleFontSize,
            AgentBadgeHeight,
            AgentBadgeHorizontalPadding,
            AgentBadgeFontSize,
            UnreadDotSize,
            FooterGap,
            FooterMinHeight,
            FooterSpacerBeforeMetadata,
            PillHeight,
            PillHorizontalPadding,
            PillFontSize,
            PillLineHeight,
            PillIconFontSize,
            PillSvgIconSize);
    }

    public static GraphNodeCardMaterialSnapshot WebMaterial()
    {
        return new GraphNodeCardMaterialSnapshot(
            CanvasBackgroundHex,
            PrimaryTextHex,
            SecondaryTextHex,
            TertiaryTextHex,
            Rgba(SurfaceHex, SurfaceOpacity),
            Rgba(SurfaceHex, StrongSurfaceOpacity),
            Rgba(StrokeHex, StrokeOpacity),
            Rgba(StrokeHex, SoftStrokeOpacity),
            Rgba(ShadowHex, DefaultShadowOpacity));
    }

    private static string Rgba(string hex, double alpha)
    {
        var clean = hex.TrimStart('#');
        var red = Convert.ToInt32(clean[..2], 16);
        var green = Convert.ToInt32(clean[2..4], 16);
        var blue = Convert.ToInt32(clean[4..6], 16);
        return $"rgba({red}, {green}, {blue}, {alpha:0.00})";
    }
}
