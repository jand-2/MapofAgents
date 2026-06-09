namespace MapofAgents.Core;

public readonly record struct ThreadNodeUpdatedPresentationSnapshot(string Text);

public readonly record struct ThreadNodeUpdatedFormatterConfig(
    int NowThresholdSeconds,
    string IntlStyle,
    double TextFontSize,
    double TextLineHeight,
    string TextForegroundHex,
    int TextMaxLines,
    IReadOnlyList<ThreadNodeUpdatedFormatterUnit> Units);

public readonly record struct ThreadNodeUpdatedFormatterUnit(
    string Unit,
    int Seconds,
    int CeilingSeconds,
    string SingularLabel,
    string PluralLabel);

public static class ThreadNodeUpdatedPresentation
{
    public const int NowThresholdSeconds = 5;
    public const string IntlStyle = "short";
    public const double TextFontSize = 11;
    public const double TextLineHeight = 13;
    public const string TextForegroundHex = GraphNodeCardPresentation.TertiaryTextHex;
    public const int TextMaxLines = 1;

    private static readonly ThreadNodeUpdatedFormatterUnit[] FormatterUnits =
    [
        new("second", 1, 60, "sec.", "sec."),
        new("minute", 60, 3_600, "min.", "min."),
        new("hour", 3_600, 86_400, "hr.", "hr."),
        new("day", 86_400, 604_800, "day", "days"),
        new("week", 604_800, 2_629_800, "wk.", "wk."),
        new("month", 2_629_800, 31_557_600, "mo.", "mo."),
        new("year", 31_557_600, int.MaxValue, "yr.", "yr.")
    ];

    public static ThreadNodeUpdatedPresentationSnapshot Resolve(
        DateTimeOffset updatedAt,
        DateTimeOffset now)
    {
        var deltaSeconds = (now - updatedAt).TotalSeconds;
        var absoluteSeconds = Math.Abs(deltaSeconds);
        if (absoluteSeconds < NowThresholdSeconds)
        {
            return new ThreadNodeUpdatedPresentationSnapshot("updated now");
        }

        var unit = UnitFor(absoluteSeconds);
        var value = Math.Max(1, (int)Math.Round(absoluteSeconds / unit.Seconds));
        var label = value == 1 ? unit.SingularLabel : unit.PluralLabel;
        var relative = deltaSeconds < 0
            ? $"in {value} {label}"
            : $"{value} {label} ago";

        return new ThreadNodeUpdatedPresentationSnapshot($"updated {relative}");
    }

    public static ThreadNodeUpdatedFormatterConfig WebFormatterConfig()
    {
        return new ThreadNodeUpdatedFormatterConfig(
            NowThresholdSeconds,
            IntlStyle,
            TextFontSize,
            TextLineHeight,
            TextForegroundHex,
            TextMaxLines,
            FormatterUnits);
    }

    private static ThreadNodeUpdatedFormatterUnit UnitFor(double absoluteSeconds)
    {
        foreach (var unit in FormatterUnits)
        {
            if (absoluteSeconds < unit.CeilingSeconds)
            {
                return unit;
            }
        }

        return FormatterUnits[^1];
    }
}
