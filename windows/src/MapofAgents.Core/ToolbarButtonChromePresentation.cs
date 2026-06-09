namespace MapofAgents.Core;

public readonly record struct ToolbarButtonChromeRoleSnapshot(
    string StyleKey,
    double MinHeight,
    double HorizontalPadding,
    double VerticalPadding,
    string BackgroundHex,
    string BorderHex,
    double BorderThickness,
    double CornerRadius,
    string ForegroundHex,
    double FontSize);

public readonly record struct ToolbarButtonChromePresentationSnapshot(
    ToolbarButtonChromeRoleSnapshot Plain,
    ToolbarButtonChromeRoleSnapshot Bordered,
    ToolbarButtonChromeRoleSnapshot Primary,
    ToolbarButtonChromeRoleSnapshot Purple);

public static class ToolbarButtonChromePresentation
{
    public const string PlainStyleKey = "ToolbarPlainButtonStyle";
    public const string PlainSplitStyleKey = "ToolbarPlainSplitButtonStyle";
    public const string BorderedStyleKey = "ToolbarButtonStyle";
    public const string BorderedSplitStyleKey = "ToolbarSplitButtonStyle";
    public const string PrimaryStyleKey = "ToolbarPrimaryButtonStyle";
    public const string PurpleStyleKey = "ToolbarPurpleButtonStyle";
    public const double MinHeight = 28;
    public const double PlainHorizontalPadding = 7;
    public const double BorderedHorizontalPadding = 9;
    public const double VerticalPadding = 3;
    public const double CornerRadius = 6;
    public const double FontSize = 13;
    public const string PlainBackgroundHex = "#00FFFFFF";
    public const string PlainBorderHex = "#00FFFFFF";
    public const double PlainBorderThickness = 0;
    public const string PlainForegroundHex = "#D7DCE5";
    public const string BorderedBackgroundHex = "#10FFFFFF";
    public const string BorderedBorderHex = "#24FFFFFF";
    public const double BorderedBorderThickness = 1;
    public const string BorderedForegroundHex = "#F2F4F7";
    public const string PrimaryBackgroundHex = "#E60A84FF";
    public const string PrimaryBorderHex = "#FF0A84FF";
    public const string PrimaryForegroundHex = "#FFFFFFFF";
    public const string PurpleBackgroundHex = "#24BF5AF2";
    public const string PurpleBorderHex = "#70BF5AF2";
    public const string PurpleForegroundHex = "#FFDDB8FF";

    public static ToolbarButtonChromePresentationSnapshot Resolve()
    {
        var bordered = Bordered(BorderedStyleKey);
        return new ToolbarButtonChromePresentationSnapshot(
            Plain(PlainStyleKey),
            bordered,
            bordered with
            {
                StyleKey = PrimaryStyleKey,
                BackgroundHex = PrimaryBackgroundHex,
                BorderHex = PrimaryBorderHex,
                ForegroundHex = PrimaryForegroundHex
            },
            bordered with
            {
                StyleKey = PurpleStyleKey,
                BackgroundHex = PurpleBackgroundHex,
                BorderHex = PurpleBorderHex,
                ForegroundHex = PurpleForegroundHex
            });
    }

    public static ToolbarButtonChromeRoleSnapshot Plain(string styleKey)
    {
        return new ToolbarButtonChromeRoleSnapshot(
            styleKey,
            MinHeight,
            PlainHorizontalPadding,
            VerticalPadding,
            PlainBackgroundHex,
            PlainBorderHex,
            PlainBorderThickness,
            CornerRadius,
            PlainForegroundHex,
            FontSize);
    }

    public static ToolbarButtonChromeRoleSnapshot Bordered(string styleKey)
    {
        return new ToolbarButtonChromeRoleSnapshot(
            styleKey,
            MinHeight,
            BorderedHorizontalPadding,
            VerticalPadding,
            BorderedBackgroundHex,
            BorderedBorderHex,
            BorderedBorderThickness,
            CornerRadius,
            BorderedForegroundHex,
            FontSize);
    }
}
