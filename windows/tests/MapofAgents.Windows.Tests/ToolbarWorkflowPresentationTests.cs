using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarWorkflowPresentationTests
{
    [TestMethod]
    public void UsesMacRectangleGroupTreatment()
    {
        var presentation = ToolbarWorkflowPresentation.Resolve();

        Assert.AreEqual("rectangle.3.group", presentation.MacSymbolName);
        Assert.IsTrue(presentation.UsesRectangleGroupIcon);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("#D7DCE5", presentation.ChevronStrokeHex);
        Assert.AreEqual("Workflow", presentation.ToolTip);
        Assert.AreEqual("Workflow", presentation.DefaultTitle);
        Assert.AreEqual("Main Workflow", ToolbarWorkflowPresentation.InitialWorkflowName);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(15, presentation.IconHeight);
        Assert.AreEqual(1, presentation.StrokeThickness);
        Assert.AreEqual(8, presentation.ChevronWidth);
        Assert.AreEqual(7, presentation.ChevronHeight);
        Assert.AreEqual(1.15, presentation.ChevronStrokeThickness);
    }

    [TestMethod]
    public void DisplayTitleFallsBackToMacWorkflowTitle()
    {
        Assert.AreEqual("Workflow", ToolbarWorkflowPresentation.DisplayTitle(null));
        Assert.AreEqual("Workflow", ToolbarWorkflowPresentation.DisplayTitle(""));
        Assert.AreEqual("Workflow", ToolbarWorkflowPresentation.DisplayTitle("   "));
        Assert.AreEqual("Primary", ToolbarWorkflowPresentation.DisplayTitle(" Primary "));
        Assert.AreEqual("Main Workflow", ToolbarWorkflowPresentation.DisplayActiveTitle(" Main Workflow ", "mapofagents"));
        Assert.AreEqual("mapofagents", ToolbarWorkflowPresentation.DisplayActiveTitle(null, "mapofagents"));
    }

    [TestMethod]
    public void MenuIconsTrackMacWorkflowSymbols()
    {
        var menu = ToolbarWorkflowPresentation.ResolveMenu();

        Assert.AreEqual(ToolbarWorkflowPresentation.ActiveWorkflowIcon, menu.ActiveWorkflowIconKind);
        Assert.AreEqual("checkmark", menu.ActiveWorkflowMacSymbolName);
        Assert.AreEqual(ToolbarWorkflowPresentation.InactiveWorkflowIcon, menu.InactiveWorkflowIconKind);
        Assert.AreEqual("circle", menu.InactiveWorkflowMacSymbolName);
        Assert.AreEqual(ToolbarWorkflowPresentation.NewWorkflowIcon, menu.NewWorkflowIconKind);
        Assert.AreEqual("plus", menu.NewWorkflowMacSymbolName);
        Assert.AreEqual(ToolbarWorkflowPresentation.RenameIcon, menu.RenameIconKind);
        Assert.AreEqual("pencil", menu.RenameMacSymbolName);
        Assert.AreEqual(ToolbarWorkflowPresentation.DuplicateIcon, menu.DuplicateIconKind);
        Assert.AreEqual("doc.on.doc", menu.DuplicateMacSymbolName);
        Assert.AreEqual(ToolbarWorkflowPresentation.DeleteIcon, menu.DeleteIconKind);
        Assert.AreEqual("trash", menu.DeleteMacSymbolName);
        Assert.AreEqual(16, menu.IconSize);
    }

    [TestMethod]
    public void NameEditorUsesMacWorkflowMenuSymbols()
    {
        var create = ToolbarWorkflowPresentation.ResolveNameEditor(ToolbarWorkflowPresentation.NameEditorCreateMode);
        var rename = ToolbarWorkflowPresentation.ResolveNameEditor(ToolbarWorkflowPresentation.NameEditorRenameMode);
        var duplicate = ToolbarWorkflowPresentation.ResolveNameEditor(ToolbarWorkflowPresentation.NameEditorDuplicateMode);

        Assert.AreEqual("New Workflow", create.Title);
        Assert.AreEqual("Create", create.ActionTitle);
        Assert.AreEqual(ToolbarWorkflowPresentation.NewWorkflowIcon, create.IconKind);
        Assert.AreEqual("plus", create.MacSymbolName);

        Assert.AreEqual("Rename Workflow", rename.Title);
        Assert.AreEqual("Rename", rename.ActionTitle);
        Assert.AreEqual(ToolbarWorkflowPresentation.RenameIcon, rename.IconKind);
        Assert.AreEqual("pencil", rename.MacSymbolName);

        Assert.AreEqual("Save Workflow Copy", duplicate.Title);
        Assert.AreEqual("Save Copy", duplicate.ActionTitle);
        Assert.AreEqual(ToolbarWorkflowPresentation.DuplicateIcon, duplicate.IconKind);
        Assert.AreEqual("doc.on.doc", duplicate.MacSymbolName);

        Assert.AreEqual("#0A84FF", rename.IconHex);
        Assert.AreEqual("#1A0A84FF", rename.BackgroundHex);
        Assert.AreEqual(16, rename.IconSize);
        Assert.AreEqual("\uE711", rename.CloseGlyph);
        Assert.AreEqual("xmark", rename.CloseMacSymbolName);
        Assert.AreEqual(24, rename.CloseButtonSize);
        Assert.AreEqual(12, rename.CloseIconSize);
    }
}
