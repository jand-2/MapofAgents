using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarSubagentsPresentationTests
{
    [TestMethod]
    public void VisibleStateUsesMacPersonPairFillTreatment()
    {
        var presentation = ToolbarSubagentsPresentation.Resolve(showsSubagents: true);

        Assert.AreEqual("person.2.fill", presentation.MacSymbolName);
        Assert.AreEqual("ToolbarPurpleButtonStyle", presentation.StyleKey);
        Assert.AreEqual("#FFDDB8FF", presentation.IconHex);
        Assert.AreEqual("#FFDDB8FF", presentation.SlashHex);
        Assert.IsFalse(presentation.ShowsSlash);
        Assert.AreEqual("Hide subagent nodes and lines", presentation.ToolTip);
        Assert.AreEqual("Subagents", presentation.AccessibilityName);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(15, presentation.IconHeight);
        Assert.AreEqual(1.8, presentation.SlashStrokeThickness);
    }

    [TestMethod]
    public void HiddenStateUsesMacPersonPairSlashTreatment()
    {
        var presentation = ToolbarSubagentsPresentation.Resolve(showsSubagents: false);

        Assert.AreEqual("person.2.slash", presentation.MacSymbolName);
        Assert.AreEqual("ToolbarButtonStyle", presentation.StyleKey);
        Assert.AreEqual("#D7DCE5", presentation.IconHex);
        Assert.AreEqual("#D7DCE5", presentation.SlashHex);
        Assert.IsTrue(presentation.ShowsSlash);
        Assert.AreEqual("Show subagent nodes and lines", presentation.ToolTip);
        Assert.AreEqual("Subagents", presentation.AccessibilityName);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(15, presentation.IconHeight);
        Assert.AreEqual(1.8, presentation.SlashStrokeThickness);
    }
}
