namespace MapofAgents.Core;

public readonly record struct ThreadTurnEventPresentationSnapshot(
    string HeaderTitle,
    string Detail,
    string WindowsGlyph,
    string ForegroundHex,
    string HeaderBackgroundHex,
    string HeaderBorderHex,
    string HeaderDetailForegroundHex,
    double HeaderHorizontalPadding,
    double HeaderVerticalPadding,
    double HeaderCornerRadius,
    double HeaderContentSpacing,
    double HeaderStatusIconSpacing,
    double HeaderStatusIconFontSize,
    double HeaderDetailFontSize,
    double HeaderMaxWidth,
    string EmptyTitle,
    string EmptyDetail,
    string EmptyWindowsGlyph,
    string EmptyBackgroundHex,
    string EmptyBorderHex,
    string EmptyForegroundHex,
    double EmptyPadding,
    double EmptyCornerRadius,
    double EmptyContentSpacing,
    double EmptyIconFontSize,
    double EmptyTextFontSize,
    double EmptyMaxWidth);

public static class ThreadTurnEventPresentation
{
    public const string RunningTitle = "Turn running";
    public const string NeedsInputTitle = "Turn needs you";
    public const string FailedTitle = "Turn failed";
    public const string CompleteTitle = "Turn";
    public const string IdleTitle = "Thread context";
    public const string UnknownTitle = "Thread update";

    public const string StartedPrefix = "Started";
    public const string CompletedPrefix = "Completed";
    public const string HeaderBackgroundHex = "#00FFFFFF";
    public const string HeaderBorderHex = "#00FFFFFF";
    public const string HeaderDetailForegroundHex = "#8F9BAA";
    public const double HeaderHorizontalPadding = 8;
    public const double HeaderVerticalPadding = 0;
    public const double HeaderCornerRadius = 0;
    public const double HeaderContentSpacing = 5;
    public const double HeaderStatusIconSpacing = 6;
    public const double HeaderStatusIconFontSize = 11;
    public const double HeaderDetailFontSize = 11;
    public const double HeaderMaxWidth = double.PositiveInfinity;
    public const string EmptyBackgroundHex = "#14A7B0BF";
    public const string EmptyBorderHex = "#00FFFFFF";
    public const string EmptyForegroundHex = TranscriptCategoryPresentation.SecondaryHex;
    public const double EmptyPadding = 10;
    public const double EmptyCornerRadius = 8;
    public const double EmptyContentSpacing = 8;
    public const double EmptyIconFontSize = 12;
    public const double EmptyTextFontSize = 12;
    public const double EmptyMaxWidth = double.PositiveInfinity;

    public static ThreadTurnEventPresentationSnapshot Resolve(LocalThreadTurn turn)
    {
        return new ThreadTurnEventPresentationSnapshot(
            HeaderTitle(turn.Status),
            Detail(turn),
            WindowsGlyph(turn.Status),
            ForegroundHex(turn.Status),
            HeaderBackgroundHex,
            HeaderBorderHex,
            HeaderDetailForegroundHex,
            HeaderHorizontalPadding,
            HeaderVerticalPadding,
            HeaderCornerRadius,
            HeaderContentSpacing,
            HeaderStatusIconSpacing,
            HeaderStatusIconFontSize,
            HeaderDetailFontSize,
            HeaderMaxWidth,
            "Turn details",
            EmptyDetail(turn),
            EmptyWindowsGlyph(turn),
            EmptyBackgroundHex,
            EmptyBorderHex,
            EmptyForegroundHex,
            EmptyPadding,
            EmptyCornerRadius,
            EmptyContentSpacing,
            EmptyIconFontSize,
            EmptyTextFontSize,
            EmptyMaxWidth);
    }

    public static string HeaderTitle(string status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => RunningTitle,
            ThreadRunStatuses.NeedsInput => NeedsInputTitle,
            ThreadRunStatuses.Failed => FailedTitle,
            ThreadRunStatuses.Complete => CompleteTitle,
            ThreadRunStatuses.Idle => IdleTitle,
            _ => UnknownTitle
        };
    }

    public static string Detail(LocalThreadTurn turn)
    {
        var parts = new List<string>
        {
            ItemsViewDisplayName(turn.ItemsView),
            $"{StartedPrefix} {StartedTimestampText(turn.StartedAt)}"
        };
        var durationText = DurationText(turn);
        if (!string.IsNullOrWhiteSpace(durationText))
        {
            parts.Add(durationText);
        }

        if (turn.CompletedAt is { } completedAt)
        {
            parts.Add($"{CompletedPrefix} {completedAt.ToLocalTime():h:mm:ss tt}");
        }

        if (!string.IsNullOrWhiteSpace(turn.Error))
        {
            parts.Add(turn.Error.Trim());
        }

        return string.Join(" - ", parts.Where(part => !string.IsNullOrWhiteSpace(part)));
    }

    public static string? DurationText(LocalThreadTurn turn)
    {
        double? seconds = turn.DurationMilliseconds.HasValue
            ? turn.DurationMilliseconds.Value / 1000.0
            : turn.CompletedAt.HasValue
                ? (turn.CompletedAt.Value - turn.StartedAt).TotalSeconds
                : null;
        if (!seconds.HasValue || seconds.Value < 0)
        {
            return null;
        }

        return seconds.Value < 1
            ? $"{Math.Max(0, (int)Math.Round(seconds.Value * 1000))} ms"
            : $"{seconds.Value:0.0}s";
    }

    public static string ItemsViewDisplayName(string itemsView)
    {
        return itemsView switch
        {
            ThreadTurnItemsViews.NotLoaded => "not loaded",
            ThreadTurnItemsViews.Summary => "summary",
            _ => "full"
        };
    }

    public static string EmptyDetail(LocalThreadTurn turn)
    {
        return turn.ItemsView switch
        {
            ThreadTurnItemsViews.NotLoaded => "Turn items are not loaded yet.",
            ThreadTurnItemsViews.Summary => "Only summary details are loaded for this turn.",
            _ when turn.Status == ThreadRunStatuses.Running => "Turn is running; no message items have arrived yet.",
            _ => "No message items were available for this turn."
        };
    }

    public static string WindowsGlyph(string status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => "\uE895",
            ThreadRunStatuses.NeedsInput => "\uE7BA",
            ThreadRunStatuses.Failed => "\uE711",
            ThreadRunStatuses.Complete => "\uE73E",
            ThreadRunStatuses.Idle => "\uE8F2",
            _ => "\uEA3A"
        };
    }

    public static string EmptyWindowsGlyph(LocalThreadTurn turn)
    {
        return turn.Status switch
        {
            ThreadRunStatuses.Running => "\uE9D5",
            ThreadRunStatuses.Failed => "\uE7BA",
            _ => "\uE8EF"
        };
    }

    public static string ForegroundHex(string status)
    {
        return status switch
        {
            ThreadRunStatuses.Running => ThreadStatusPresentation.BlueHex,
            ThreadRunStatuses.NeedsInput => ThreadStatusPresentation.OrangeHex,
            ThreadRunStatuses.Failed => ThreadStatusPresentation.RedHex,
            _ => TranscriptCategoryPresentation.SecondaryHex
        };
    }

    private static string StartedTimestampText(DateTimeOffset startedAt)
    {
        return startedAt.ToLocalTime().ToString("MMM d, h:mm:ss tt");
    }
}
