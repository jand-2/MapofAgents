namespace MapofAgents.Core;

public readonly record struct CanvasEdgeControlStyleSnapshot(
    string Glyph,
    bool UsesThreadPairIcon,
    string TintHex,
    string StrokeCss,
    string SelectedBackgroundCss,
    string HelpText,
    double LabelOffset);

public readonly record struct CanvasEdgeControlPolicySnapshot(
    bool ShowsControlsForAllStoredGraphEdges);

public readonly record struct CanvasEdgeControlLayoutSnapshot(
    double Gap,
    double MinWidth,
    double MinHeight,
    double HorizontalPadding,
    double VerticalPadding,
    double BorderWidth,
    double ShadowYOffset,
    double ShadowRadius,
    double ShadowOpacity,
    double BackgroundOpacity,
    double HoverBackgroundOpacity,
    double LabelFontSize,
    double LabelLineHeight,
    int LabelFontWeight,
    double IconFontSize,
    int IconFontWeight,
    double ThreadPairIconWidth,
    double ThreadPairIconHeight);

public readonly record struct CanvasEdgeArrowTreatmentSnapshot(
    bool DrawsSolidConnector,
    double ConnectorStartT,
    double ArrowTailT,
    double DefaultHeadSize,
    double SelectedHeadSize);

public readonly record struct CanvasEdgeVisualTreatmentSnapshot(
    string SecondaryHex,
    string WorkflowEdgeCss,
    string WorkflowLabelHex,
    string WorkflowLabelFillCss,
    string WorkflowLabelStrokeCss,
    string GridMinorCss,
    string GridMajorCss,
    string GridReducedCss);

public readonly record struct CanvasEdgeEditorPresentationSnapshot(
    string Title,
    string Glyph,
    string MacSymbolName,
    string IconForegroundHex,
    string IconBackgroundHex,
    double IconFontSize);

public static class CanvasEdgePresentation
{
    public const string SecondaryTintHex = "#A7B0BF";
    public const string GreenTintHex = "#30D158";
    public const string BlueTintHex = "#0A84FF";
    public const string OrangeTintHex = "#FF9F0A";
    public const string FallbackGlyph = "\uE8F3";
    public const string FolderGlyph = "\uE8B7";
    public const string ThreadGlyph = "\uE8F2";
    public const string NoteGlyph = "\uE70B";
    public const string CreatedByGlyph = "\uE710";
    public const string MessageLineEditorGlyph = "\uE724";
    public const string WorkflowNoteEditorGlyph = "\uE8F3";
    public const string MessageLineMacSymbolName = "paperplane";
    public const string WorkflowNoteMacSymbolName = "line.diagonal";
    public const string EditorIconBackgroundHex = "#1A30D158";
    public const double EditorIconFontSize = 12;
    public const double ArrowConnectorStartT = 0.93;
    public const double ArrowTailT = 0.9;
    public const double DefaultArrowHeadSize = 11;
    public const double SelectedArrowHeadSize = 14;
    public const double WorkflowEdgeOpacity = 0.52;
    public const double WorkflowLabelFillOpacity = 0.12;
    public const double WorkflowLabelStrokeOpacity = 0.38;
    public const double GridMinorOpacity = 0.12;
    public const double GridMajorOpacity = 0.20;
    public const double GridReducedOpacity = 0.14;
    public const double ControlGap = 4;
    public const double ControlMinWidth = 44;
    public const double ControlMinHeight = 28;
    public const double ControlHorizontalPadding = 10;
    public const double ControlVerticalPadding = 6;
    public const double ControlBorderWidth = 1;
    public const double ControlShadowYOffset = 2;
    public const double ControlShadowRadius = 5;
    public const double ControlShadowOpacity = 0.28;
    public const double ControlBackgroundOpacity = 0.72;
    public const double ControlHoverBackgroundOpacity = 0.82;
    public const double ControlLabelFontSize = 11;
    public const double ControlLabelLineHeight = 13;
    public const int ControlLabelFontWeight = 600;
    public const double ControlIconFontSize = 10;
    public const int ControlIconFontWeight = 700;
    public const double ControlThreadPairIconWidth = 13;
    public const double ControlThreadPairIconHeight = 12;

    public static string EditorTitle(CanvasEdge edge)
    {
        return Editor(edge).Title;
    }

    public static CanvasEdgeEditorPresentationSnapshot Editor(CanvasEdge edge)
    {
        return edge.Kind == EdgeKinds.ThreadMessage
            ? new CanvasEdgeEditorPresentationSnapshot(
                "Message Line",
                MessageLineEditorGlyph,
                MessageLineMacSymbolName,
                GreenTintHex,
                EditorIconBackgroundHex,
                EditorIconFontSize)
            : new CanvasEdgeEditorPresentationSnapshot(
                "Workflow Note",
                WorkflowNoteEditorGlyph,
                WorkflowNoteMacSymbolName,
                GreenTintHex,
                EditorIconBackgroundHex,
                EditorIconFontSize);
    }

    public static string Label(CanvasEdge edge)
    {
        var customLabel = edge.Label?.Trim();
        if (!string.IsNullOrWhiteSpace(customLabel))
        {
            return string.Equals(edge.Kind, EdgeKinds.CreatedBy, StringComparison.Ordinal) &&
                string.Equals(customLabel, "created by", StringComparison.OrdinalIgnoreCase)
                    ? "created"
                    : customLabel;
        }

        return DefaultLabel(edge.Kind);
    }

    public static string DefaultLabel(string kind)
    {
        return kind switch
        {
            EdgeKinds.MachineFolder => "folder",
            EdgeKinds.FolderThread => "thread",
            EdgeKinds.MachineThread => "thread",
            EdgeKinds.ManualNote => "note",
            EdgeKinds.ThreadMessage => "message",
            EdgeKinds.CreatedBy => "created",
            _ => "line"
        };
    }

    public static string KindLabel(string kind)
    {
        return kind switch
        {
            EdgeKinds.ThreadMessage => "Message route",
            EdgeKinds.CreatedBy => "Created by",
            EdgeKinds.MachineFolder => "Machine folder",
            EdgeKinds.FolderThread => "Folder thread",
            EdgeKinds.MachineThread => "Machine thread",
            EdgeKinds.ManualNote => "Manual line",
            _ => "Line"
        };
    }

    public static CanvasEdgeControlStyleSnapshot ControlStyle(string? kind)
    {
        return kind switch
        {
            EdgeKinds.MachineFolder => Snapshot(
                FolderGlyph,
                usesThreadPairIcon: false,
                SecondaryTintHex,
                "rgba(167, 176, 191, 0.76)",
                "rgba(167, 176, 191, 0.68)",
                "Edit folder link",
                labelOffset: 12),
            EdgeKinds.FolderThread or EdgeKinds.MachineThread => Snapshot(
                ThreadGlyph,
                usesThreadPairIcon: false,
                SecondaryTintHex,
                "rgba(167, 176, 191, 0.76)",
                "rgba(167, 176, 191, 0.68)",
                "Edit thread link",
                labelOffset: 12),
            EdgeKinds.ManualNote => Snapshot(
                NoteGlyph,
                usesThreadPairIcon: false,
                GreenTintHex,
                "rgba(48, 209, 88, 0.76)",
                "rgba(48, 209, 88, 0.88)",
                "Edit note link",
                labelOffset: 14),
            EdgeKinds.ThreadMessage => Snapshot(
                string.Empty,
                usesThreadPairIcon: true,
                BlueTintHex,
                "rgba(10, 132, 255, 0.76)",
                "rgba(10, 132, 255, 0.92)",
                "Edit message link",
                labelOffset: -16),
            EdgeKinds.CreatedBy => Snapshot(
                CreatedByGlyph,
                usesThreadPairIcon: false,
                OrangeTintHex,
                "rgba(255, 159, 10, 0.76)",
                "rgba(255, 159, 10, 0.88)",
                "Edit created thread link",
                labelOffset: 16),
            _ => Snapshot(
                FallbackGlyph,
                usesThreadPairIcon: false,
                SecondaryTintHex,
                "rgba(167, 176, 191, 0.76)",
                "rgba(167, 176, 191, 0.68)",
                "Edit line",
                labelOffset: 12)
        };
    }

    public static IReadOnlyDictionary<string, CanvasEdgeControlStyleSnapshot> WebControlStyleMap()
    {
        return new Dictionary<string, CanvasEdgeControlStyleSnapshot>(StringComparer.Ordinal)
        {
            [EdgeKinds.MachineFolder] = ControlStyle(EdgeKinds.MachineFolder),
            [EdgeKinds.FolderThread] = ControlStyle(EdgeKinds.FolderThread),
            [EdgeKinds.MachineThread] = ControlStyle(EdgeKinds.MachineThread),
            [EdgeKinds.ManualNote] = ControlStyle(EdgeKinds.ManualNote),
            [EdgeKinds.ThreadMessage] = ControlStyle(EdgeKinds.ThreadMessage),
            [EdgeKinds.CreatedBy] = ControlStyle(EdgeKinds.CreatedBy),
            ["line"] = ControlStyle(null)
        };
    }

    public static CanvasEdgeControlPolicySnapshot WebControlPolicy()
    {
        return new CanvasEdgeControlPolicySnapshot(
            ShowsControlsForAllStoredGraphEdges: true);
    }

    public static CanvasEdgeControlLayoutSnapshot WebControlLayout()
    {
        return new CanvasEdgeControlLayoutSnapshot(
            ControlGap,
            ControlMinWidth,
            ControlMinHeight,
            ControlHorizontalPadding,
            ControlVerticalPadding,
            ControlBorderWidth,
            ControlShadowYOffset,
            ControlShadowRadius,
            ControlShadowOpacity,
            ControlBackgroundOpacity,
            ControlHoverBackgroundOpacity,
            ControlLabelFontSize,
            ControlLabelLineHeight,
            ControlLabelFontWeight,
            ControlIconFontSize,
            ControlIconFontWeight,
            ControlThreadPairIconWidth,
            ControlThreadPairIconHeight);
    }

    public static CanvasEdgeArrowTreatmentSnapshot WebArrowTreatment()
    {
        return new CanvasEdgeArrowTreatmentSnapshot(
            DrawsSolidConnector: true,
            ArrowConnectorStartT,
            ArrowTailT,
            DefaultArrowHeadSize,
            SelectedArrowHeadSize);
    }

    public static CanvasEdgeVisualTreatmentSnapshot WebVisualTreatment()
    {
        return new CanvasEdgeVisualTreatmentSnapshot(
            SecondaryTintHex,
            Rgba(SecondaryTintHex, WorkflowEdgeOpacity),
            SecondaryTintHex,
            Rgba(SecondaryTintHex, WorkflowLabelFillOpacity),
            Rgba(SecondaryTintHex, WorkflowLabelStrokeOpacity),
            Rgba(SecondaryTintHex, GridMinorOpacity),
            Rgba(SecondaryTintHex, GridMajorOpacity),
            Rgba(SecondaryTintHex, GridReducedOpacity));
    }

    private static CanvasEdgeControlStyleSnapshot Snapshot(
        string glyph,
        bool usesThreadPairIcon,
        string tintHex,
        string strokeCss,
        string selectedBackgroundCss,
        string helpText,
        double labelOffset)
    {
        return new CanvasEdgeControlStyleSnapshot(
            glyph,
            usesThreadPairIcon,
            tintHex,
            strokeCss,
            selectedBackgroundCss,
            helpText,
            labelOffset);
    }

    private static string Rgba(string hex, double alpha)
    {
        var clean = hex.TrimStart('#');
        var red = Convert.ToInt32(clean[..2], 16);
        var green = Convert.ToInt32(clean[2..4], 16);
        var blue = Convert.ToInt32(clean[4..6], 16);
        return $"rgba({red}, {green}, {blue}, {alpha:0.00})";
    }
}
