namespace MapofAgents.Core;

public readonly record struct ReaderHeaderControlPresentationSnapshot(
    double PickerHeight,
    double PickerCornerRadius,
    double PickerBorderThickness,
    double PickerHorizontalPadding,
    double PickerVerticalPadding,
    double PickerFontSize,
    string PickerBackgroundHex,
    string PickerBorderHex,
    string PickerForegroundHex,
    string PickerPointerOverBackgroundHex,
    string PickerPressedBackgroundHex,
    string PickerFocusedBorderHex,
    string PickerChevronForegroundHex,
    double IconButtonSize,
    double IconButtonCornerRadius,
    double IconButtonBorderThickness,
    string IconButtonBackgroundHex,
    string IconButtonBorderHex,
    string IconButtonForegroundHex,
    double AddRemoveIconFontSize,
    double CloseIconFontSize);

public static class ReaderHeaderControlPresentation
{
    public const double PickerHeight = 30;
    public const double PickerCornerRadius = 6;
    public const double PickerBorderThickness = 1;
    public const double PickerHorizontalPadding = 8;
    public const double PickerVerticalPadding = 3;
    public const double PickerFontSize = 13;
    public const string PickerBackgroundHex = "#142A2C30";
    public const string PickerBorderHex = "#24FFFFFF";
    public const string PickerForegroundHex = "#F2F4F7";
    public const string PickerPointerOverBackgroundHex = "#1F2A2C30";
    public const string PickerPressedBackgroundHex = "#292A2C30";
    public const string PickerFocusedBorderHex = "#660A84FF";
    public const string PickerChevronForegroundHex = "#A7B0BF";
    public const double IconButtonSize = 24;
    public const double IconButtonCornerRadius = 12;
    public const double IconButtonBorderThickness = 0;
    public const string IconButtonBackgroundHex = "#00FFFFFF";
    public const string IconButtonBorderHex = "#00FFFFFF";
    public const string IconButtonForegroundHex = "#A7B0BF";
    public const double AddRemoveIconFontSize = 12;
    public const double CloseIconFontSize = 12;

    public static ReaderHeaderControlPresentationSnapshot Resolve()
    {
        return new ReaderHeaderControlPresentationSnapshot(
            PickerHeight,
            PickerCornerRadius,
            PickerBorderThickness,
            PickerHorizontalPadding,
            PickerVerticalPadding,
            PickerFontSize,
            PickerBackgroundHex,
            PickerBorderHex,
            PickerForegroundHex,
            PickerPointerOverBackgroundHex,
            PickerPressedBackgroundHex,
            PickerFocusedBorderHex,
            PickerChevronForegroundHex,
            IconButtonSize,
            IconButtonCornerRadius,
            IconButtonBorderThickness,
            IconButtonBackgroundHex,
            IconButtonBorderHex,
            IconButtonForegroundHex,
            AddRemoveIconFontSize,
            CloseIconFontSize);
    }
}
