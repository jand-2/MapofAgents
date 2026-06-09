using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CanvasEdgePresentationTests
{
    [TestMethod]
    public void EditorTitleMatchesMacSelectionInspectorTitle()
    {
        Assert.AreEqual(
            "Message Line",
            CanvasEdgePresentation.EditorTitle(new CanvasEdge { Kind = EdgeKinds.ThreadMessage }));
        Assert.AreEqual(
            "Workflow Note",
            CanvasEdgePresentation.EditorTitle(new CanvasEdge { Kind = EdgeKinds.ManualNote }));
        Assert.AreEqual(
            "Workflow Note",
            CanvasEdgePresentation.EditorTitle(new CanvasEdge { Kind = EdgeKinds.FolderThread }));
    }

    [TestMethod]
    public void EditorPresentationExposesMacEdgeHeaderSymbols()
    {
        var message = CanvasEdgePresentation.Editor(new CanvasEdge { Kind = EdgeKinds.ThreadMessage });
        var note = CanvasEdgePresentation.Editor(new CanvasEdge { Kind = EdgeKinds.ManualNote });

        Assert.AreEqual(CanvasEdgePresentation.MessageLineEditorGlyph, message.Glyph);
        Assert.AreEqual("paperplane", message.MacSymbolName);
        Assert.AreEqual(CanvasEdgePresentation.WorkflowNoteEditorGlyph, note.Glyph);
        Assert.AreEqual("line.diagonal", note.MacSymbolName);
        Assert.AreEqual(CanvasEdgePresentation.GreenTintHex, message.IconForegroundHex);
        Assert.AreEqual(CanvasEdgePresentation.EditorIconBackgroundHex, note.IconBackgroundHex);
        Assert.AreEqual(12, message.IconFontSize, 0.001);
    }

    [TestMethod]
    public void LabelUsesMacDefaultEdgeLabels()
    {
        Assert.AreEqual("folder", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.MachineFolder }));
        Assert.AreEqual("thread", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.FolderThread }));
        Assert.AreEqual("thread", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.MachineThread }));
        Assert.AreEqual("note", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.ManualNote }));
        Assert.AreEqual("message", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.ThreadMessage }));
        Assert.AreEqual("created", CanvasEdgePresentation.Label(new CanvasEdge { Kind = EdgeKinds.CreatedBy }));
    }

    [TestMethod]
    public void LabelNormalizesCreatedByCustomLabel()
    {
        var edge = new CanvasEdge
        {
            Kind = EdgeKinds.CreatedBy,
            Label = "Created By"
        };

        Assert.AreEqual("created", CanvasEdgePresentation.Label(edge));
    }

    [TestMethod]
    public void LabelKeepsOtherCustomLabels()
    {
        var edge = new CanvasEdge
        {
            Kind = EdgeKinds.ManualNote,
            Label = "handoff"
        };

        Assert.AreEqual("handoff", CanvasEdgePresentation.Label(edge));
    }

    [TestMethod]
    public void MessageLineControlUsesMacDoubleChatIconTreatment()
    {
        var style = CanvasEdgePresentation.ControlStyle(EdgeKinds.ThreadMessage);

        Assert.IsTrue(style.UsesThreadPairIcon);
        Assert.AreEqual(string.Empty, style.Glyph);
        Assert.AreEqual(CanvasEdgePresentation.BlueTintHex, style.TintHex);
        Assert.AreEqual("rgba(10, 132, 255, 0.76)", style.StrokeCss);
        Assert.AreEqual("rgba(10, 132, 255, 0.92)", style.SelectedBackgroundCss);
        Assert.AreEqual("Edit message link", style.HelpText);
        Assert.AreEqual(-16, style.LabelOffset);
    }

    [TestMethod]
    public void EdgeControlStylesExposeMacLabelOffsetsForWebRenderer()
    {
        Assert.AreEqual(12, CanvasEdgePresentation.ControlStyle(EdgeKinds.MachineFolder).LabelOffset);
        Assert.AreEqual(12, CanvasEdgePresentation.ControlStyle(EdgeKinds.FolderThread).LabelOffset);
        Assert.AreEqual(12, CanvasEdgePresentation.ControlStyle(EdgeKinds.MachineThread).LabelOffset);
        Assert.AreEqual(14, CanvasEdgePresentation.ControlStyle(EdgeKinds.ManualNote).LabelOffset);
        Assert.AreEqual(16, CanvasEdgePresentation.ControlStyle(EdgeKinds.CreatedBy).LabelOffset);
    }

    [TestMethod]
    public void WebControlStyleMapIncludesRendererFallbackKeys()
    {
        var map = CanvasEdgePresentation.WebControlStyleMap();

        Assert.IsTrue(map.ContainsKey(EdgeKinds.MachineFolder));
        Assert.IsTrue(map.ContainsKey(EdgeKinds.FolderThread));
        Assert.IsTrue(map.ContainsKey(EdgeKinds.MachineThread));
        Assert.IsTrue(map.ContainsKey(EdgeKinds.ManualNote));
        Assert.IsTrue(map.ContainsKey(EdgeKinds.ThreadMessage));
        Assert.IsTrue(map.ContainsKey(EdgeKinds.CreatedBy));
        Assert.IsTrue(map.ContainsKey("line"));
        Assert.IsTrue(map[EdgeKinds.ThreadMessage].UsesThreadPairIcon);
    }

    [TestMethod]
    public void WebControlPolicyShowsControlsForEveryStoredGraphEdgeLikeMac()
    {
        var policy = CanvasEdgePresentation.WebControlPolicy();

        Assert.IsTrue(policy.ShowsControlsForAllStoredGraphEdges);
        Assert.AreEqual(
            "Edit thread link",
            CanvasEdgePresentation.ControlStyle(EdgeKinds.FolderThread).HelpText);
    }

    [TestMethod]
    public void WebControlLayoutMatchesMacEdgeControlPillMetrics()
    {
        var layout = CanvasEdgePresentation.WebControlLayout();

        Assert.AreEqual(4, layout.Gap);
        Assert.AreEqual(44, layout.MinWidth);
        Assert.AreEqual(28, layout.MinHeight);
        Assert.AreEqual(10, layout.HorizontalPadding);
        Assert.AreEqual(6, layout.VerticalPadding);
        Assert.AreEqual(1, layout.BorderWidth);
        Assert.AreEqual(2, layout.ShadowYOffset);
        Assert.AreEqual(5, layout.ShadowRadius);
        Assert.AreEqual(0.28, layout.ShadowOpacity);
        Assert.AreEqual(0.72, layout.BackgroundOpacity);
        Assert.AreEqual(0.82, layout.HoverBackgroundOpacity);
        Assert.AreEqual(11, layout.LabelFontSize);
        Assert.AreEqual(13, layout.LabelLineHeight);
        Assert.AreEqual(600, layout.LabelFontWeight);
        Assert.AreEqual(10, layout.IconFontSize);
        Assert.AreEqual(700, layout.IconFontWeight);
        Assert.AreEqual(13, layout.ThreadPairIconWidth);
        Assert.AreEqual(12, layout.ThreadPairIconHeight);
    }

    [TestMethod]
    public void WebArrowTreatmentMatchesMacSolidConnectorAndHeadMetrics()
    {
        var treatment = CanvasEdgePresentation.WebArrowTreatment();

        Assert.IsTrue(treatment.DrawsSolidConnector);
        Assert.AreEqual(0.93, treatment.ConnectorStartT, 0.001);
        Assert.AreEqual(0.9, treatment.ArrowTailT, 0.001);
        Assert.AreEqual(11, treatment.DefaultHeadSize);
        Assert.AreEqual(14, treatment.SelectedHeadSize);
    }

    [TestMethod]
    public void WebVisualTreatmentUsesMacSecondaryCanvasAndWorkflowLineColors()
    {
        var treatment = CanvasEdgePresentation.WebVisualTreatment();

        Assert.AreEqual(CanvasEdgePresentation.SecondaryTintHex, treatment.SecondaryHex);
        Assert.AreEqual("rgba(167, 176, 191, 0.52)", treatment.WorkflowEdgeCss);
        Assert.AreEqual(CanvasEdgePresentation.SecondaryTintHex, treatment.WorkflowLabelHex);
        Assert.AreEqual("rgba(167, 176, 191, 0.12)", treatment.WorkflowLabelFillCss);
        Assert.AreEqual("rgba(167, 176, 191, 0.38)", treatment.WorkflowLabelStrokeCss);
        Assert.AreEqual("rgba(167, 176, 191, 0.12)", treatment.GridMinorCss);
        Assert.AreEqual("rgba(167, 176, 191, 0.20)", treatment.GridMajorCss);
        Assert.AreEqual("rgba(167, 176, 191, 0.14)", treatment.GridReducedCss);
    }
}
