using System.Globalization;
using System.Text;

namespace MapofAgents.Core;

public sealed record CodexAutomationSummary(
    string Id,
    string Kind,
    string Name,
    string Prompt,
    string Status,
    string RRule,
    string? TargetThreadID,
    string? ExecutionEnvironment,
    string? Model,
    string? ReasoningEffort,
    DateTimeOffset? CreatedAt,
    DateTimeOffset? UpdatedAt,
    DateTimeOffset? LastRunAt,
    string ConfigurationPath)
{
    public bool IsActive => string.Equals(Status, CodexAutomationStatuses.Active, StringComparison.OrdinalIgnoreCase);

    public bool IsHeartbeat => string.Equals(Kind, "heartbeat", StringComparison.OrdinalIgnoreCase);

    public string RunsInDisplayName
    {
        get
        {
            if (IsHeartbeat)
            {
                return "Chat";
            }

            return string.IsNullOrWhiteSpace(ExecutionEnvironment)
                ? "Workspace"
                : CultureInfo.CurrentCulture.TextInfo.ToTitleCase(ExecutionEnvironment.Trim());
        }
    }

    public string IntervalDisplayName => new CodexAutomationSchedule(RRule).DisplayName;

    public DateTimeOffset? NextRun(
        DateTimeOffset? referenceDate = null,
        TimeZoneInfo? timeZone = null)
    {
        if (!IsActive)
        {
            return null;
        }

        return new CodexAutomationSchedule(RRule).NextRun(
            referenceDate ?? DateTimeOffset.Now,
            CreatedAt ?? UpdatedAt,
            timeZone);
    }
}

public sealed record CodexAutomationEdit(
    string Id,
    string Name,
    string Prompt,
    string Status,
    string RRule);

public static class CodexAutomationStatuses
{
    public const string Active = "ACTIVE";
    public const string Paused = "PAUSED";
}

public sealed class CodexAutomationStoreException : Exception
{
    private CodexAutomationStoreException(string message)
        : base(message)
    {
    }

    public static CodexAutomationStoreException AutomationNotFound(string id)
    {
        return new CodexAutomationStoreException($"Could not find Codex automation {id}.");
    }

    public static CodexAutomationStoreException InvalidAutomation(string path)
    {
        return new CodexAutomationStoreException($"Codex automation file is missing required fields: {path}");
    }

    public static CodexAutomationStoreException InvalidAutomationDirectory(string path)
    {
        return new CodexAutomationStoreException($"Codex automation directory is unavailable: {path}");
    }
}

public sealed class CodexAutomationStore
{
    public CodexAutomationStore(string? codexHome = null)
    {
        CodexHome = string.IsNullOrWhiteSpace(codexHome)
            ? DefaultCodexHome()
            : codexHome.Trim();
    }

    public string CodexHome { get; }

    public static string DefaultCodexHome(
        IReadOnlyDictionary<string, string?>? environment = null,
        string? homeDirectory = null)
    {
        var source = environment ?? Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(
                entry => entry.Key?.ToString() ?? "",
                entry => entry.Value?.ToString(),
                StringComparer.OrdinalIgnoreCase);
        if (source.TryGetValue("CODEX_HOME", out var codexHome) &&
            !string.IsNullOrWhiteSpace(codexHome))
        {
            return codexHome.Trim();
        }

        var home = string.IsNullOrWhiteSpace(homeDirectory)
            ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            : homeDirectory.Trim();
        return Path.Combine(home, ".codex");
    }

    public IReadOnlyList<CodexAutomationSummary> LoadAutomations()
    {
        var automationsDirectory = Path.Combine(CodexHome, "automations");
        if (!Directory.Exists(automationsDirectory))
        {
            return [];
        }

        return Directory
            .EnumerateDirectories(automationsDirectory)
            .Select(directory => Path.Combine(directory, "automation.toml"))
            .Where(File.Exists)
            .Select(LoadAutomation)
            .OrderBy(automation => automation.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(automation => automation.Id, StringComparer.Ordinal)
            .ToList();
    }

    public IReadOnlyDictionary<string, CodexAutomationSummary> LoadAutomationsByThreadId()
    {
        var result = new Dictionary<string, CodexAutomationSummary>(StringComparer.OrdinalIgnoreCase);
        foreach (var automation in LoadAutomations())
        {
            var threadID = automation.TargetThreadID?.Trim();
            if (string.IsNullOrWhiteSpace(threadID))
            {
                continue;
            }

            result[threadID] = result.TryGetValue(threadID, out var existing)
                ? PreferredAutomation(existing, automation)
                : automation;
        }

        return result;
    }

    public CodexAutomationSummary Save(CodexAutomationEdit edit)
    {
        var filePath = Path.Combine(CodexHome, "automations", edit.Id, "automation.toml");
        if (!File.Exists(filePath))
        {
            throw CodexAutomationStoreException.AutomationNotFound(edit.Id);
        }

        var original = File.ReadAllText(filePath, Encoding.UTF8);
        var updated = UpdateAutomationToml(original, edit, DateTimeOffset.UtcNow);
        File.WriteAllText(filePath, updated, Encoding.UTF8);
        return LoadAutomation(filePath);
    }

    public static CodexAutomationSummary LoadAutomation(string filePath)
    {
        var text = File.ReadAllText(filePath, Encoding.UTF8);
        var fields = CodexAutomationToml.Parse(text);
        if (!fields.TryGetValue("id", out var id) ||
            string.IsNullOrWhiteSpace(id) ||
            !fields.TryGetValue("name", out var name) ||
            string.IsNullOrWhiteSpace(name) ||
            !fields.TryGetValue("rrule", out var rrule) ||
            string.IsNullOrWhiteSpace(rrule))
        {
            throw CodexAutomationStoreException.InvalidAutomation(filePath);
        }

        return new CodexAutomationSummary(
            id.Trim(),
            TrimOrDefault(fields.GetValueOrDefault("kind"), "cron"),
            name.Trim(),
            fields.GetValueOrDefault("prompt") ?? "",
            TrimOrDefault(fields.GetValueOrDefault("status"), CodexAutomationStatuses.Paused),
            rrule.Trim(),
            NilIfBlank(fields.GetValueOrDefault("target_thread_id")),
            NilIfBlank(fields.GetValueOrDefault("execution_environment")),
            NilIfBlank(fields.GetValueOrDefault("model")),
            NilIfBlank(fields.GetValueOrDefault("reasoning_effort")),
            ParseDate(fields.GetValueOrDefault("created_at")),
            ParseDate(fields.GetValueOrDefault("updated_at")),
            ParseDate(fields.GetValueOrDefault("last_run_at")),
            filePath);
    }

    public static CodexAutomationSummary PreferredAutomation(
        CodexAutomationSummary lhs,
        CodexAutomationSummary rhs)
    {
        if (lhs.IsActive != rhs.IsActive)
        {
            return rhs.IsActive ? rhs : lhs;
        }

        var lhsDate = lhs.UpdatedAt ?? lhs.CreatedAt ?? DateTimeOffset.MinValue;
        var rhsDate = rhs.UpdatedAt ?? rhs.CreatedAt ?? DateTimeOffset.MinValue;
        return rhsDate >= lhsDate ? rhs : lhs;
    }

    public static string UpdateAutomationToml(
        string toml,
        CodexAutomationEdit edit,
        DateTimeOffset updatedAt)
    {
        var replacements = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["name"] = TomlValue(edit.Name),
            ["prompt"] = TomlValue(edit.Prompt),
            ["status"] = TomlValue(edit.Status.ToUpperInvariant()),
            ["rrule"] = TomlValue(edit.RRule),
            ["updated_at"] = TomlValue(updatedAt.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture))
        };
        var existingKeys = CodexAutomationToml.Parse(toml).Keys.ToHashSet(StringComparer.Ordinal);
        var output = new List<string>();
        var lines = toml.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var index = 0;

        while (index < lines.Length)
        {
            var line = lines[index];
            var parsed = CodexAutomationToml.LineKeyAndValue(line);
            if (parsed is { } keyValue &&
                replacements.TryGetValue(keyValue.Key, out var replacement))
            {
                output.Add($"{keyValue.Key} = {replacement}");
                var trimmedValue = keyValue.Value.TrimStart();
                if (trimmedValue.StartsWith("\"\"\"", StringComparison.Ordinal) &&
                    !trimmedValue[3..].Contains("\"\"\"", StringComparison.Ordinal))
                {
                    index += 1;
                    while (index < lines.Length)
                    {
                        if (lines[index].Contains("\"\"\"", StringComparison.Ordinal))
                        {
                            break;
                        }

                        index += 1;
                    }
                }
            }
            else
            {
                output.Add(line);
            }

            index += 1;
        }

        foreach (var key in new[] { "name", "prompt", "status", "rrule", "updated_at" })
        {
            if (!existingKeys.Contains(key) && replacements.TryGetValue(key, out var replacement))
            {
                output.Add($"{key} = {replacement}");
            }
        }

        return string.Join("\n", output);
    }

    public static string TomlValue(string value)
    {
        var builder = new StringBuilder("\"");
        foreach (var character in value)
        {
            builder.Append(character switch
            {
                '\\' => "\\\\",
                '"' => "\\\"",
                '\n' => "\\n",
                '\r' => "\\r",
                '\t' => "\\t",
                _ => character.ToString()
            });
        }

        builder.Append('"');
        return builder.ToString();
    }

    private static string TrimOrDefault(string? value, string fallback)
    {
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }

    private static string? NilIfBlank(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static DateTimeOffset? ParseDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return DateTimeOffset.TryParse(
            value.Trim(),
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var parsed)
            ? parsed
            : null;
    }
}

public sealed record CodexAutomationSchedule(string RRule)
{
    public string DisplayName
    {
        get
        {
            var parts = Components;
            var interval = Math.Max(1, IntValue(parts, "INTERVAL", 1));
            return parts.GetValueOrDefault("FREQ")?.ToUpperInvariant() switch
            {
                "MINUTELY" => interval == 1 ? "Every minute" : $"Every {interval} minutes",
                "HOURLY" => interval == 1 ? "Hourly" : $"Every {interval} hours",
                "DAILY" => interval == 1 ? "Daily" : $"Every {interval} days",
                "WEEKLY" => interval == 1 ? "Weekly" : $"Every {interval} weeks",
                "MONTHLY" => interval == 1 ? "Monthly" : $"Every {interval} months",
                _ => "Custom"
            };
        }
    }

    public DateTimeOffset? NextRun(
        DateTimeOffset referenceDate,
        DateTimeOffset? anchor = null,
        TimeZoneInfo? timeZone = null)
    {
        var parts = Components;
        var interval = Math.Max(1, IntValue(parts, "INTERVAL", 1));
        return parts.GetValueOrDefault("FREQ")?.ToUpperInvariant() switch
        {
            "MINUTELY" => NextIntervalDate(referenceDate, anchor, TimeSpan.FromMinutes(interval)),
            "HOURLY" => NextIntervalDate(referenceDate, anchor, TimeSpan.FromHours(interval)),
            "DAILY" => NextDailyDate(referenceDate, interval, parts, timeZone),
            "WEEKLY" => NextWeeklyDate(referenceDate, interval, parts, timeZone),
            _ => null
        };
    }

    public IReadOnlyDictionary<string, string> Components
    {
        get
        {
            var normalized = RRule.StartsWith("RRULE:", StringComparison.OrdinalIgnoreCase)
                ? RRule["RRULE:".Length..]
                : RRule;
            return normalized
                .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(part => part.Split('=', 2, StringSplitOptions.TrimEntries))
                .Where(pieces => pieces.Length == 2 && pieces[0].Length > 0)
                .ToDictionary(
                    pieces => pieces[0].ToUpperInvariant(),
                    pieces => pieces[1],
                    StringComparer.OrdinalIgnoreCase);
        }
    }

    private static DateTimeOffset? NextIntervalDate(
        DateTimeOffset referenceDate,
        DateTimeOffset? anchor,
        TimeSpan interval)
    {
        if (anchor is null)
        {
            return referenceDate.Add(interval);
        }

        if (anchor > referenceDate)
        {
            return anchor;
        }

        var elapsedTicks = referenceDate.UtcDateTime.Ticks - anchor.Value.UtcDateTime.Ticks;
        var steps = (elapsedTicks / interval.Ticks) + 1;
        return anchor.Value.AddTicks(steps * interval.Ticks);
    }

    private static DateTimeOffset? NextDailyDate(
        DateTimeOffset referenceDate,
        int interval,
        IReadOnlyDictionary<string, string> parts,
        TimeZoneInfo? timeZone)
    {
        var local = ToScheduleTime(referenceDate, timeZone);
        var hour = Clamp(IntValue(parts, "BYHOUR", 9), 0, 23);
        var minute = Clamp(IntValue(parts, "BYMINUTE", 0), 0, 59);
        var candidate = new DateTimeOffset(
            local.Year,
            local.Month,
            local.Day,
            hour,
            minute,
            0,
            local.Offset);
        while (candidate <= local)
        {
            candidate = candidate.AddDays(interval);
        }

        return FromScheduleTime(candidate, referenceDate, timeZone);
    }

    private static DateTimeOffset? NextWeeklyDate(
        DateTimeOffset referenceDate,
        int interval,
        IReadOnlyDictionary<string, string> parts,
        TimeZoneInfo? timeZone)
    {
        var local = ToScheduleTime(referenceDate, timeZone);
        var targetDays = (parts.GetValueOrDefault("BYDAY") ?? "")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(WeekdayFor)
            .OfType<DayOfWeek>()
            .ToList();
        if (targetDays.Count == 0)
        {
            targetDays.Add(local.DayOfWeek);
        }

        var hour = Clamp(IntValue(parts, "BYHOUR", 9), 0, 23);
        var minute = Clamp(IntValue(parts, "BYMINUTE", 0), 0, 59);
        DateTimeOffset? best = null;
        for (var dayOffset = 0; dayOffset < Math.Max(2, interval + 1) * 7; dayOffset++)
        {
            var day = local.AddDays(dayOffset);
            if (!targetDays.Contains(day.DayOfWeek))
            {
                continue;
            }

            var candidate = new DateTimeOffset(
                day.Year,
                day.Month,
                day.Day,
                hour,
                minute,
                0,
                day.Offset);
            if (candidate <= local)
            {
                continue;
            }

            best = best is null || candidate < best ? candidate : best;
        }

        return best is null ? null : FromScheduleTime(best.Value, referenceDate, timeZone);
    }

    private static DateTimeOffset ToScheduleTime(DateTimeOffset value, TimeZoneInfo? timeZone)
    {
        return timeZone is null ? value : TimeZoneInfo.ConvertTime(value, timeZone);
    }

    private static DateTimeOffset FromScheduleTime(
        DateTimeOffset value,
        DateTimeOffset referenceDate,
        TimeZoneInfo? timeZone)
    {
        return timeZone is null
            ? value
            : TimeZoneInfo.ConvertTime(value, TimeZoneInfo.Utc).ToOffset(referenceDate.Offset);
    }

    private static int IntValue(IReadOnlyDictionary<string, string> parts, string key, int fallback)
    {
        return parts.TryGetValue(key, out var value) &&
            int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : fallback;
    }

    private static int Clamp(int value, int lowerBound, int upperBound)
    {
        return Math.Min(Math.Max(value, lowerBound), upperBound);
    }

    private static DayOfWeek? WeekdayFor(string value)
    {
        return value.ToUpperInvariant() switch
        {
            "SU" => DayOfWeek.Sunday,
            "MO" => DayOfWeek.Monday,
            "TU" => DayOfWeek.Tuesday,
            "WE" => DayOfWeek.Wednesday,
            "TH" => DayOfWeek.Thursday,
            "FR" => DayOfWeek.Friday,
            "SA" => DayOfWeek.Saturday,
            _ => null
        };
    }
}

public enum CodexAutomationScheduleFrequency
{
    Daily,
    Weekly,
    Custom
}

public sealed record CodexAutomationScheduleDraft(
    CodexAutomationScheduleFrequency Frequency,
    int Hour,
    int Minute,
    string WeeklyDays)
{
    public static CodexAutomationScheduleDraft FromRRule(string rrule)
    {
        var parts = new CodexAutomationSchedule(rrule).Components;
        var hour = Clamp(IntValue(parts, "BYHOUR", 9), 0, 23);
        var minute = Clamp(IntValue(parts, "BYMINUTE", 0), 0, 59);
        var weeklyDays = parts.GetValueOrDefault("BYDAY")?.Trim() ?? "";
        var frequency = parts.GetValueOrDefault("FREQ")?.ToUpperInvariant() switch
        {
            "DAILY" => CodexAutomationScheduleFrequency.Daily,
            "WEEKLY" => CodexAutomationScheduleFrequency.Weekly,
            _ => CodexAutomationScheduleFrequency.Custom
        };
        return new CodexAutomationScheduleDraft(frequency, hour, minute, weeklyDays);
    }

    private static int IntValue(IReadOnlyDictionary<string, string> parts, string key, int fallback)
    {
        return parts.TryGetValue(key, out var value) &&
            int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : fallback;
    }

    private static int Clamp(int value, int lowerBound, int upperBound)
    {
        return Math.Min(Math.Max(value, lowerBound), upperBound);
    }
}

public static class CodexAutomationToml
{
    public static Dictionary<string, string> Parse(string text)
    {
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        var index = 0;
        while (index < lines.Length)
        {
            var parsed = LineKeyAndValue(lines[index]);
            if (parsed is null)
            {
                index += 1;
                continue;
            }

            var trimmedValue = parsed.Value.Value.TrimStart();
            if (trimmedValue.StartsWith("\"\"\"", StringComparison.Ordinal))
            {
                var value = trimmedValue[3..];
                var end = value.IndexOf("\"\"\"", StringComparison.Ordinal);
                if (end >= 0)
                {
                    result[parsed.Value.Key] = value[..end];
                }
                else
                {
                    var builder = new StringBuilder(value);
                    index += 1;
                    while (index < lines.Length)
                    {
                        var line = lines[index];
                        var closing = line.IndexOf("\"\"\"", StringComparison.Ordinal);
                        if (builder.Length > 0)
                        {
                            builder.Append('\n');
                        }

                        if (closing >= 0)
                        {
                            builder.Append(line[..closing]);
                            break;
                        }

                        builder.Append(line);
                        index += 1;
                    }

                    result[parsed.Value.Key] = builder.ToString();
                }
            }
            else
            {
                result[parsed.Value.Key] = ParseValue(trimmedValue);
            }

            index += 1;
        }

        return result;
    }

    public static (string Key, string Value)? LineKeyAndValue(string line)
    {
        var trimmed = line.Trim();
        var equals = trimmed.IndexOf('=');
        if (trimmed.Length == 0 ||
            trimmed.StartsWith('#') ||
            trimmed.StartsWith('[') ||
            equals < 1)
        {
            return null;
        }

        var key = trimmed[..equals].Trim();
        if (key.Length == 0)
        {
            return null;
        }

        var value = trimmed[(equals + 1)..];
        return (key, value);
    }

    private static string ParseValue(string rawValue)
    {
        if (rawValue.StartsWith('"'))
        {
            return ParseBasicString(rawValue);
        }

        if (rawValue.StartsWith('\''))
        {
            var value = rawValue[1..];
            var end = value.IndexOf('\'');
            return end >= 0 ? value[..end] : value;
        }

        return rawValue.Split('#', 2)[0].Trim();
    }

    private static string ParseBasicString(string rawValue)
    {
        var escaped = false;
        var builder = new StringBuilder();
        foreach (var character in rawValue.Skip(1))
        {
            if (escaped)
            {
                builder.Append(character switch
                {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '"' => '"',
                    '\\' => '\\',
                    _ => character
                });
                escaped = false;
                continue;
            }

            if (character == '\\')
            {
                escaped = true;
                continue;
            }

            if (character == '"')
            {
                break;
            }

            builder.Append(character);
        }

        return builder.ToString();
    }
}
