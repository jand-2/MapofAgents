using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarCreationPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacCreationButtonSymbols()
    {
        var presentation = ToolbarCreationPresentation.Resolve();

        Assert.AreEqual("folder.badge.plus", presentation.FolderMacSymbolName);
        Assert.AreEqual("plus.bubble", presentation.ThreadMacSymbolName);
        Assert.AreEqual("#D7DCE5", presentation.FolderStrokeHex);
        Assert.AreEqual("#D7DCE5", presentation.FolderBadgeFillHex);
        Assert.AreEqual("#1D1E20", presentation.FolderPlusHex);
        Assert.AreEqual("#FFFFFFFF", presentation.ThreadStrokeHex);
        Assert.AreEqual(18, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(1.15, presentation.StrokeThickness);
        Assert.AreEqual(1.25, presentation.ThreadStrokeThickness);
        Assert.AreEqual(5.8, presentation.BadgeSize);
        Assert.IsTrue(presentation.BadgeX > presentation.IconWidth / 2);
        Assert.IsTrue(presentation.BadgeY < presentation.IconHeight / 2);
        Assert.AreEqual(1.15, presentation.PlusStrokeThickness);
        Assert.AreEqual("Add folder", presentation.FolderAccessibilityName);
        Assert.AreEqual("Create Codex thread", presentation.ThreadAccessibilityName);
    }
}
