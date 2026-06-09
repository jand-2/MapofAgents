namespace MapofAgents.Core;

public readonly record struct GraphNodeLinkActionStatePresentation(
    string State,
    string MacSymbolName,
    string Glyph,
    string Label,
    string IconKind);

public readonly record struct GraphNodeLinkActionWebConfig(
    GraphNodeLinkActionStatePresentation Draw,
    GraphNodeLinkActionStatePresentation Cancel,
    GraphNodeLinkActionStatePresentation Complete,
    string ActiveHex,
    double ActiveBorderWidth,
    double ActiveBorderRadius);

public static class GraphNodeLinkActionPresentation
{
    public const string DrawState = "draw";
    public const string CancelState = "cancel";
    public const string CompleteState = "complete";
    public const string DrawMacSymbolName = "point.3.connected.trianglepath.dotted";
    public const string CancelMacSymbolName = "xmark.circle";
    public const string CompleteMacSymbolName = "checkmark.circle";
    public const string DrawGlyph = "\uE8F3";
    public const string CancelGlyph = "\uE711";
    public const string CompleteGlyph = "\uE73E";
    public const string DottedTrianglePathIconKind = "dottedTrianglePath";
    public const string FluentGlyphIconKind = "fluentGlyph";
    public const string DrawLabel = "Draw connection";
    public const string CancelLabel = "Cancel connection";
    public const string CompleteLabel = "Complete connection";
    public const string ActiveHex = "#30D158";
    public const double ActiveBorderWidth = 1.3;
    public const double ActiveBorderRadius = 999;

    public static GraphNodeLinkActionStatePresentation Resolve(string state)
    {
        return state switch
        {
            CancelState => State(CancelState, CancelMacSymbolName, CancelGlyph, CancelLabel, FluentGlyphIconKind),
            CompleteState => State(CompleteState, CompleteMacSymbolName, CompleteGlyph, CompleteLabel, FluentGlyphIconKind),
            _ => State(DrawState, DrawMacSymbolName, DrawGlyph, DrawLabel, DottedTrianglePathIconKind)
        };
    }

    public static GraphNodeLinkActionWebConfig WebConfig()
    {
        return new GraphNodeLinkActionWebConfig(
            Resolve(DrawState),
            Resolve(CancelState),
            Resolve(CompleteState),
            ActiveHex,
            ActiveBorderWidth,
            ActiveBorderRadius);
    }

    private static GraphNodeLinkActionStatePresentation State(
        string state,
        string macSymbolName,
        string glyph,
        string label,
        string iconKind)
    {
        return new GraphNodeLinkActionStatePresentation(
            state,
            macSymbolName,
            glyph,
            label,
            iconKind);
    }
}
