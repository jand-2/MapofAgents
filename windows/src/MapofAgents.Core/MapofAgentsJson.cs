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

[JsonConverter(typeof(JsonRpcRequestIdConverter))]
public readonly record struct JsonRpcRequestId
{
    private JsonRpcRequestId(string? stringValue, long? integerValue)
    {
        StringValue = stringValue;
        IntegerValue = integerValue;
    }

    public string? StringValue { get; }

    public long? IntegerValue { get; }

    public static JsonRpcRequestId FromString(string value) => new(value, null);

    public static JsonRpcRequestId FromInteger(long value) => new(null, value);

    public override string ToString() => StringValue ?? IntegerValue?.ToString() ?? "";
}

public sealed class JsonRpcRequestIdConverter : JsonConverter<JsonRpcRequestId>
{
    public override JsonRpcRequestId Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        return reader.TokenType switch
        {
            JsonTokenType.String => JsonRpcRequestId.FromString(
                reader.GetString() ?? throw new JsonException("Request IDs cannot be null.")),
            JsonTokenType.Number => JsonRpcRequestId.FromInteger(reader.GetInt64()),
            _ => throw new JsonException("Request IDs must be strings or integers.")
        };
    }

    public override void Write(
        Utf8JsonWriter writer,
        JsonRpcRequestId value,
        JsonSerializerOptions options)
    {
        if (value.StringValue is { } stringValue)
        {
            writer.WriteStringValue(stringValue);
            return;
        }

        if (value.IntegerValue is { } integerValue)
        {
            writer.WriteNumberValue(integerValue);
            return;
        }

        throw new JsonException("Request IDs must contain a string or integer value.");
    }
}

/// Reads the canonical object-keyed map and the alternating key/value array
/// emitted by older Swift JSONEncoder versions. Writers always emit the
/// canonical object form.
public sealed class ObjectOrAlternatingArrayDictionaryConverter<TValue>
    : JsonConverter<Dictionary<string, TValue>>
{
    public override Dictionary<string, TValue> Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        var result = new Dictionary<string, TValue>(StringComparer.Ordinal);

        if (reader.TokenType == JsonTokenType.StartObject)
        {
            while (reader.Read() && reader.TokenType != JsonTokenType.EndObject)
            {
                if (reader.TokenType != JsonTokenType.PropertyName)
                {
                    throw new JsonException("Expected a dictionary property name.");
                }

                var key = reader.GetString() ??
                    throw new JsonException("Dictionary keys cannot be null.");
                if (!reader.Read())
                {
                    throw new JsonException("Expected a dictionary value.");
                }

                var decodedValue = JsonSerializer.Deserialize<TValue>(ref reader, options);
                if (decodedValue is null)
                {
                    throw new JsonException($"Dictionary value for '{key}' cannot be null.");
                }
                result.Add(key, decodedValue);
            }

            return result;
        }

        if (reader.TokenType == JsonTokenType.StartArray)
        {
            while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
            {
                if (reader.TokenType != JsonTokenType.String)
                {
                    throw new JsonException("Legacy dictionary keys must be strings.");
                }

                var key = reader.GetString() ??
                    throw new JsonException("Legacy dictionary keys cannot be null.");
                if (!reader.Read() || reader.TokenType == JsonTokenType.EndArray)
                {
                    throw new JsonException("Legacy dictionaries must contain key/value pairs.");
                }

                var decodedValue = JsonSerializer.Deserialize<TValue>(ref reader, options);
                if (decodedValue is null)
                {
                    throw new JsonException($"Dictionary value for '{key}' cannot be null.");
                }
                result.Add(key, decodedValue);
            }

            return result;
        }

        throw new JsonException("Expected an object or legacy alternating key/value array.");
    }

    public override void Write(
        Utf8JsonWriter writer,
        Dictionary<string, TValue> value,
        JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        foreach (var pair in value.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            writer.WritePropertyName(pair.Key);
            JsonSerializer.Serialize(writer, pair.Value, options);
        }
        writer.WriteEndObject();
    }
}
