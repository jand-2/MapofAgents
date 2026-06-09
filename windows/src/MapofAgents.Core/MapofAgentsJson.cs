using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public static class MapofAgentsJson
{
    public static JsonSerializerOptions Options { get; } = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
}
