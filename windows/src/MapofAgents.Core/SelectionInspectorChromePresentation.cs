namespace MapofAgents.Core;

public readonly record struct SelectionInspectorChromePresentationSnapshot(
    double FieldHeight,
    double FieldCornerRadius,
    double FieldBorderThickness,
    double FieldHorizontalPadding,
    double FieldVerticalPadding,
    double FieldFontSize,
    string FieldBackgroundHex,
    string FieldBorderHex,
    string FieldForegroundHex,
    string PlaceholderForegroundHex,
    string FieldPointerOverBackgroundHex,
    string FieldFocusedBorderHex,
    double DetailFontSize,
    string DetailForegroundHex,
    double CloseButtonSize,
    double CloseButtonCornerRadius,
    double CloseIconFontSize,
    double ActionRowSpacing,
    double ActionButtonMinHeight,
    double ActionButtonCornerRadius,
    double ActionButtonBorderThickness,
    double ActionButtonHorizontalPadding,
    double ActionButtonVerticalPadding,
    double ActionContentSpacing,
    double ActionIconFontSize,
    double ActionFontSize,
    string SaveBackgroundHex,
    string SaveBorderHex,
    string SaveForegroundHex,
    string DeleteBackgroundHex,
    string DeleteBorderHex,
    string DeleteForegroundHex);

public static class SelectionInspectorChromePresentation
{
    public const double FieldHeight = 30;
    public const double FieldCornerRadius = 6;
    public const double FieldBorderThickness = 1;
    public const double FieldHorizontalPadding = 8;
    public const double FieldVerticalPadding = 3;
    public const double FieldFontSize = 13;
    public const string FieldBackgroundHex = "#142A2C30";
    public const string FieldBorderHex = "#24FFFFFF";
    public const string FieldForegroundHex = "#F2F4F7";
    public const string PlaceholderForegroundHex = "#8F9BAA";
    public const string FieldPointerOverBackgroundHex = "#1F2A2C30";
    public const string FieldFocusedBorderHex = "#660A84FF";
    public const double DetailFontSize = 12;
    public const string DetailForegroundHex = "#A7B0BF";
    public const double CloseButtonSize = 24;
    public const double CloseButtonCornerRadius = 12;
    public const double CloseIconFontSize = 12;
    public const double ActionRowSpacing = 8;
    public const double ActionButtonMinHeight = 28;
    public const double ActionButtonCornerRadius = 6;
    public const double ActionButtonBorderThickness = 1;
    public const double ActionButtonHorizontalPadding = 9;
    public const double ActionButtonVerticalPadding = 4;
    public const double ActionContentSpacing = 7;
    public const double ActionIconFontSize = 14;
    public const double ActionFontSize = 13;
    public const string SaveBackgroundHex = "#E60A84FF";
    public const string SaveBorderHex = "#FF0A84FF";
    public const string SaveForegroundHex = "#FFFFFFFF";
    public const string DeleteBackgroundHex = "#18B42318";
    public const string DeleteBorderHex = "#40B42318";
    public const string DeleteForegroundHex = "#FCA5A5";

    public static SelectionInspectorChromePresentationSnapshot Resolve()
    {
        return new SelectionInspectorChromePresentationSnapshot(
            FieldHeight,
            FieldCornerRadius,
            FieldBorderThickness,
            FieldHorizontalPadding,
            FieldVerticalPadding,
            FieldFontSize,
            FieldBackgroundHex,
            FieldBorderHex,
            FieldForegroundHex,
            PlaceholderForegroundHex,
            FieldPointerOverBackgroundHex,
            FieldFocusedBorderHex,
            DetailFontSize,
            DetailForegroundHex,
            CloseButtonSize,
            CloseButtonCornerRadius,
            CloseIconFontSize,
            ActionRowSpacing,
            ActionButtonMinHeight,
            ActionButtonCornerRadius,
            ActionButtonBorderThickness,
            ActionButtonHorizontalPadding,
            ActionButtonVerticalPadding,
            ActionContentSpacing,
            ActionIconFontSize,
            ActionFontSize,
            SaveBackgroundHex,
            SaveBorderHex,
            SaveForegroundHex,
            DeleteBackgroundHex,
            DeleteBorderHex,
            DeleteForegroundHex);
    }
}
