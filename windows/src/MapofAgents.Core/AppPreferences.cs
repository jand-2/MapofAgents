using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public sealed class AppPreferences
{
    [JsonPropertyName("showSubagents")]
    public bool ShowSubagents { get; set; } = true;

    [JsonPropertyName("notifyOnCompleted")]
    public bool NotifyOnCompleted { get; set; }

    [JsonPropertyName("notifyOnNeedsInput")]
    public bool NotifyOnNeedsInput { get; set; } = true;

    [JsonPropertyName("notifyOnFailed")]
    public bool NotifyOnFailed { get; set; } = true;

    [JsonPropertyName("codexRemotesCollapsed")]
    public bool CodexRemotesCollapsed { get; set; }

    [JsonPropertyName("tailnetCollapsed")]
    public bool TailnetCollapsed { get; set; }

    [JsonPropertyName("threadInboxCollapsed")]
    public bool ThreadInboxCollapsed { get; set; }

    [JsonPropertyName("activityRailCollapsed")]
    public bool ActivityRailCollapsed { get; set; }

    [JsonPropertyName("attentionRailCollapsed")]
    public bool AttentionRailCollapsed { get; set; }

    [JsonPropertyName("runtimeDiagnosticsCollapsed")]
    public bool RuntimeDiagnosticsCollapsed { get; set; }
}

public sealed class AppPreferencesStore
{
    private const string FileName = "preferences.json";

    public AppPreferencesStore(string? applicationDataDirectory = null)
    {
        ApplicationDataDirectory = string.IsNullOrWhiteSpace(applicationDataDirectory)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "MapofAgents")
            : applicationDataDirectory;
    }

    public string ApplicationDataDirectory { get; }

    public string PreferencesPath => Path.Combine(ApplicationDataDirectory, FileName);

    public AppPreferences Load()
    {
        try
        {
            if (!File.Exists(PreferencesPath))
            {
                return new AppPreferences();
            }

            using var stream = File.OpenRead(PreferencesPath);
            return JsonSerializer.Deserialize<AppPreferences>(stream, MapofAgentsJson.Options)
                ?? new AppPreferences();
        }
        catch (JsonException)
        {
            return new AppPreferences();
        }
        catch (IOException)
        {
            return new AppPreferences();
        }
        catch (UnauthorizedAccessException)
        {
            return new AppPreferences();
        }
    }

    public void Save(AppPreferences preferences)
    {
        Directory.CreateDirectory(ApplicationDataDirectory);
        var tempPath = $"{PreferencesPath}.tmp";
        using (var stream = File.Create(tempPath))
        {
            JsonSerializer.Serialize(stream, preferences, MapofAgentsJson.Options);
        }

        if (File.Exists(PreferencesPath))
        {
            File.Replace(tempPath, PreferencesPath, null);
        }
        else
        {
            File.Move(tempPath, PreferencesPath);
        }
    }
}
