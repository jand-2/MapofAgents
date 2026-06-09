namespace MapofAgents.Core;

public readonly record struct PairingContentPresentationSnapshot(
    double SurfacePadding,
    double SurfaceSpacing,
    double HeaderSpacing,
    double HeaderIconTileSize,
    double HeaderIconCornerRadius,
    double HeaderIconFontSize,
    string HeaderIconBackgroundHex,
    string HeaderIconForegroundHex,
    double HeaderTextSpacing,
    double HeaderTitleFontSize,
    double HeaderSubtitleFontSize,
    double HeaderActionButtonSize,
    double BodySpacing,
    double StatusSpacing,
    double StatusIconFontSize,
    double StatusTextFontSize,
    double DetailPadding,
    double DetailCornerRadius,
    double DetailFontSize,
    double NetworkAccessFontSize,
    double LoadingWidth,
    double LoadingHeight,
    double QrSize,
    double QrCornerRadius,
    double QrImagePadding,
    double QrDetailSpacing,
    double GeneratedDetailsWidth,
    double GeneratedDetailsSpacing,
    double ActionButtonContentSpacing,
    double ExpiryFontSize,
    double ImportPanelSpacing,
    double ImportTextBoxMinHeight,
    double PreviewPanelPadding,
    double PreviewPanelCornerRadius);

public static class PairingContentPresentation
{
    public const double SurfacePadding = 14;
    public const double SurfaceSpacing = 14;
    public const double HeaderSpacing = 10;
    public const double HeaderIconTileSize = 26;
    public const double HeaderIconCornerRadius = 6;
    public const double HeaderIconFontSize = 13;
    public const string HeaderIconBackgroundHex = "#1A0A84FF";
    public const string HeaderIconForegroundHex = "#0A84FF";
    public const double HeaderTextSpacing = 1;
    public const double HeaderTitleFontSize = 16;
    public const double HeaderSubtitleFontSize = 12;
    public const double HeaderActionButtonSize = 24;
    public const double BodySpacing = 10;
    public const double StatusSpacing = 7;
    public const double StatusIconFontSize = 13;
    public const double StatusTextFontSize = 12;
    public const double DetailPadding = 10;
    public const double DetailCornerRadius = 8;
    public const double DetailFontSize = 12;
    public const double NetworkAccessFontSize = 11;
    public const double LoadingWidth = 430;
    public const double LoadingHeight = 188;
    public const double QrSize = 188;
    public const double QrCornerRadius = 8;
    public const double QrImagePadding = 10;
    public const double QrDetailSpacing = 14;
    public const double GeneratedDetailsWidth = 230;
    public const double GeneratedDetailsSpacing = 10;
    public const double ActionButtonContentSpacing = 7;
    public const double ExpiryFontSize = 10;
    public const double ImportPanelSpacing = 10;
    public const double ImportTextBoxMinHeight = 76;
    public const double PreviewPanelPadding = 10;
    public const double PreviewPanelCornerRadius = 8;

    public static PairingContentPresentationSnapshot Resolve()
    {
        return new PairingContentPresentationSnapshot(
            SurfacePadding,
            SurfaceSpacing,
            HeaderSpacing,
            HeaderIconTileSize,
            HeaderIconCornerRadius,
            HeaderIconFontSize,
            HeaderIconBackgroundHex,
            HeaderIconForegroundHex,
            HeaderTextSpacing,
            HeaderTitleFontSize,
            HeaderSubtitleFontSize,
            HeaderActionButtonSize,
            BodySpacing,
            StatusSpacing,
            StatusIconFontSize,
            StatusTextFontSize,
            DetailPadding,
            DetailCornerRadius,
            DetailFontSize,
            NetworkAccessFontSize,
            LoadingWidth,
            LoadingHeight,
            QrSize,
            QrCornerRadius,
            QrImagePadding,
            QrDetailSpacing,
            GeneratedDetailsWidth,
            GeneratedDetailsSpacing,
            ActionButtonContentSpacing,
            ExpiryFontSize,
            ImportPanelSpacing,
            ImportTextBoxMinHeight,
            PreviewPanelPadding,
            PreviewPanelCornerRadius);
    }
}
