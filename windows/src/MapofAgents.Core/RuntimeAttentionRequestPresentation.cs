using System.Text.Json;

namespace MapofAgents.Core;

public readonly record struct RuntimeAttentionResponseChoiceSnapshot(string Label, string Value);

public static class RuntimeAttentionRequestPresentation
{
    public static IReadOnlyList<RuntimeAttentionResponseChoiceSnapshot> TypedResponseChoices(
        RuntimeAttentionRequest request)
    {
        if (QuestionResponseChoices(request.RequestParams) is { Count: > 0 } questionChoices)
        {
            return questionChoices;
        }

        if (request.Method.Contains("elicitation/request", StringComparison.OrdinalIgnoreCase) &&
            ElicitationSchema(request.RequestParams) is { } schema &&
            EnumFieldChoices(schema) is { Count: > 0 } enumChoices)
        {
            return enumChoices;
        }

        return request.ResponseChoices
            .Select(choice => new RuntimeAttentionResponseChoiceSnapshot(
                string.IsNullOrWhiteSpace(choice.Label) ? choice.Value : choice.Label,
                choice.Value ?? ""))
            .Where(choice => !string.IsNullOrWhiteSpace(choice.Label))
            .ToList();
    }

    public static string InitialTypedResponseValue(RuntimeAttentionRequest request)
    {
        return InitialTypedResponseValue(request, TypedResponseChoices(request));
    }

    public static string InitialTypedResponseValue(
        RuntimeAttentionRequest request,
        IReadOnlyList<RuntimeAttentionResponseChoiceSnapshot> choices)
    {
        if (choices.Count == 0)
        {
            return "";
        }

        if (request.Method.Contains("elicitation/request", StringComparison.OrdinalIgnoreCase) &&
            ElicitationSchema(request.RequestParams) is { } schema &&
            SingleEnumField(schema) is { } enumField &&
            TryGetJsonString(enumField, "default", out var defaultValue) &&
            ChoiceValueMatching(defaultValue, choices) is { } matchingValue)
        {
            return matchingValue;
        }

        return choices[0].Value;
    }

    private static List<RuntimeAttentionResponseChoiceSnapshot>? QuestionResponseChoices(JsonElement? requestParams)
    {
        if (!TryGetProperty(requestParams, "questions", out var questions) ||
            questions.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        foreach (var question in questions.EnumerateArray())
        {
            if (!TryGetProperty(question, "options", out var options) ||
                options.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            var choices = new List<RuntimeAttentionResponseChoiceSnapshot>();
            foreach (var option in options.EnumerateArray())
            {
                if (TryQuestionOption(option, out var choice))
                {
                    choices.Add(choice);
                }
            }

            if (choices.Count > 0)
            {
                return choices;
            }
        }

        return null;
    }

    private static bool TryQuestionOption(
        JsonElement option,
        out RuntimeAttentionResponseChoiceSnapshot choice)
    {
        if (option.ValueKind == JsonValueKind.String)
        {
            var stringOption = option.GetString()?.Trim() ?? "";
            choice = new RuntimeAttentionResponseChoiceSnapshot(stringOption, stringOption);
            return !string.IsNullOrWhiteSpace(stringOption);
        }

        if (option.ValueKind != JsonValueKind.Object ||
            !TryGetJsonString(option, "label", out var label))
        {
            choice = default;
            return false;
        }

        var value = TryGetJsonString(option, "value", out var explicitValue)
            ? explicitValue
            : TryGetJsonString(option, "id", out var id)
                ? id
                : label;
        choice = new RuntimeAttentionResponseChoiceSnapshot(label, value);
        return true;
    }

    private static JsonElement? ElicitationSchema(JsonElement? requestParams)
    {
        foreach (var key in new[] { "requestedSchema", "requested_schema", "schema" })
        {
            if (TryGetProperty(requestParams, key, out var schema) &&
                schema.ValueKind == JsonValueKind.Object)
            {
                return schema;
            }
        }

        if (!TryGetProperty(requestParams, "request", out var request) ||
            request.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        foreach (var key in new[] { "requestedSchema", "requested_schema" })
        {
            if (TryGetProperty(request, key, out var schema) &&
                schema.ValueKind == JsonValueKind.Object)
            {
                return schema;
            }
        }

        return null;
    }

    private static List<RuntimeAttentionResponseChoiceSnapshot>? EnumFieldChoices(JsonElement schema)
    {
        if (SingleEnumField(schema) is not { } enumField)
        {
            return null;
        }

        return ChoicesFromField(enumField);
    }

    private static JsonElement? SingleEnumField(JsonElement schema)
    {
        if (!TryGetProperty(schema, "properties", out var properties) ||
            properties.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        JsonElement? field = null;
        var count = 0;
        foreach (var property in properties.EnumerateObject())
        {
            if (ChoicesFromField(property.Value) is null)
            {
                continue;
            }

            field = property.Value;
            count++;
        }

        return count == 1 ? field : null;
    }

    private static List<RuntimeAttentionResponseChoiceSnapshot>? ChoicesFromField(JsonElement field)
    {
        if (TryGetJsonString(field, "type", out var type) &&
            string.Equals(type, "array", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (TryGetProperty(field, "enum", out var enumValues) &&
            enumValues.ValueKind == JsonValueKind.Array)
        {
            var choices = enumValues
                .EnumerateArray()
                .Where(value => value.ValueKind == JsonValueKind.String)
                .Select(value =>
                {
                    var text = value.GetString()?.Trim() ?? "";
                    return new RuntimeAttentionResponseChoiceSnapshot(text, text);
                })
                .Where(choice => !string.IsNullOrWhiteSpace(choice.Value))
                .ToList();
            return choices.Count == 0 ? null : choices;
        }

        var variants = VariantArray(field);
        if (variants is null)
        {
            return null;
        }

        var options = new List<RuntimeAttentionResponseChoiceSnapshot>();
        foreach (var variant in variants.Value.EnumerateArray())
        {
            if (VariantChoice(variant) is { } choice)
            {
                options.Add(choice);
            }
        }

        return options.Count == 0 ? null : options;
    }

    private static JsonElement? VariantArray(JsonElement field)
    {
        if (TryGetProperty(field, "oneOf", out var oneOf) &&
            oneOf.ValueKind == JsonValueKind.Array)
        {
            return oneOf;
        }

        if (TryGetProperty(field, "anyOf", out var anyOf) &&
            anyOf.ValueKind == JsonValueKind.Array)
        {
            return anyOf;
        }

        return null;
    }

    private static RuntimeAttentionResponseChoiceSnapshot? VariantChoice(JsonElement variant)
    {
        var value = TryGetJsonString(variant, "const", out var constValue)
            ? constValue
            : FirstEnumString(variant);

        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var label = TryGetJsonString(variant, "title", out var title)
            ? title
            : TryGetJsonString(variant, "label", out var explicitLabel)
                ? explicitLabel
                : TryGetJsonString(variant, "description", out var description)
                    ? description
                    : value;

        return new RuntimeAttentionResponseChoiceSnapshot(label, value);
    }

    private static string? ChoiceValueMatching(
        string value,
        IReadOnlyList<RuntimeAttentionResponseChoiceSnapshot> choices)
    {
        var trimmed = value.Trim();
        foreach (var choice in choices)
        {
            if (string.Equals(choice.Value, trimmed, StringComparison.OrdinalIgnoreCase) ||
                string.Equals(choice.Label, trimmed, StringComparison.OrdinalIgnoreCase))
            {
                return choice.Value;
            }
        }

        return null;
    }

    private static string FirstEnumString(JsonElement variant)
    {
        if (!TryGetProperty(variant, "enum", out var enumValues) ||
            enumValues.ValueKind != JsonValueKind.Array)
        {
            return "";
        }

        foreach (var value in enumValues.EnumerateArray())
        {
            if (value.ValueKind == JsonValueKind.String)
            {
                return value.GetString()?.Trim() ?? "";
            }
        }

        return "";
    }

    private static bool TryGetProperty(JsonElement? element, string propertyName, out JsonElement property)
    {
        if (element is { ValueKind: JsonValueKind.Object } objectElement &&
            objectElement.TryGetProperty(propertyName, out property))
        {
            return true;
        }

        property = default;
        return false;
    }

    private static bool TryGetProperty(JsonElement element, string propertyName, out JsonElement property)
    {
        if (element.ValueKind == JsonValueKind.Object &&
            element.TryGetProperty(propertyName, out property))
        {
            return true;
        }

        property = default;
        return false;
    }

    private static bool TryGetJsonString(JsonElement element, string propertyName, out string value)
    {
        if (TryGetProperty(element, propertyName, out var property) &&
            property.ValueKind == JsonValueKind.String)
        {
            value = property.GetString()?.Trim() ?? "";
            return !string.IsNullOrWhiteSpace(value);
        }

        value = "";
        return false;
    }
}
