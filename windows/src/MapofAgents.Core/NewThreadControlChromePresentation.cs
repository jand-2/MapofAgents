namespace MapofAgents.Core;

public readonly record struct NewThreadControlChromePresentationSnapshot(
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
    string FieldPressedBackgroundHex,
    string FieldFocusedBorderHex,
    string PickerChevronForegroundHex,
    double PromptHorizontalPadding,
    double PromptVerticalPadding,
    double CreateButtonWidth,
    double CreateButtonHeight,
    double CreateButtonCornerRadius,
    double CreateButtonBorderThickness,
    string CreateButtonBackgroundHex,
    string CreateButtonBorderHex,
    string CreateButtonForegroundHex);

public static class NewThreadControlChromePresentation
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
    public const string FieldPressedBackgroundHex = "#292A2C30";
    public const string FieldFocusedBorderHex = "#660A84FF";
    public const string PickerChevronForegroundHex = "#A7B0BF";
    public const double PromptHorizontalPadding = 9;
    public const double PromptVerticalPadding = 6;
    public const double CreateButtonWidth = 38;
    public const double CreateButtonHeight = 34;
    public const double CreateButtonCornerRadius = 7;
    public const double CreateButtonBorderThickness = 1;
    public const string CreateButtonBackgroundHex = "#E60A84FF";
    public const string CreateButtonBorderHex = "#FF0A84FF";
    public const string CreateButtonForegroundHex = "#FFFFFFFF";

    public static NewThreadControlChromePresentationSnapshot Resolve()
    {
        return new NewThreadControlChromePresentationSnapshot(
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
            FieldPressedBackgroundHex,
            FieldFocusedBorderHex,
            PickerChevronForegroundHex,
            PromptHorizontalPadding,
            PromptVerticalPadding,
            CreateButtonWidth,
            CreateButtonHeight,
            CreateButtonCornerRadius,
            CreateButtonBorderThickness,
            CreateButtonBackgroundHex,
            CreateButtonBorderHex,
            CreateButtonForegroundHex);
    }
}
