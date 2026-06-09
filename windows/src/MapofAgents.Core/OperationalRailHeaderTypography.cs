namespace MapofAgents.Core;

public readonly record struct OperationalRailHeaderTypographySnapshot(
    string MacFontStyleName,
    double TitleFontSize,
    string TitleFontWeightName,
    double IconTitleSpacing);

public static class OperationalRailHeaderTypography
{
    public const string MacFontStyleName = "headline";
    public const double TitleFontSize = 13;
    public const string TitleFontWeightName = "SemiBold";
    public const double IconTitleSpacing = 8;

    public static OperationalRailHeaderTypographySnapshot Resolve()
    {
        return new OperationalRailHeaderTypographySnapshot(
            MacFontStyleName,
            TitleFontSize,
            TitleFontWeightName,
            IconTitleSpacing);
    }
}
