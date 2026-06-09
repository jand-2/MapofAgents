using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxHeaderPresentationTests
{
    [TestMethod]
    public void UsesMacTrayFullTreatment()
    {
        var presentation = ThreadInboxHeaderPresentation.Resolve();

        Assert.IsTrue(presentation.UsesTrayFullIcon);
        Assert.AreEqual("tray.full", presentation.TrayMacSymbolName);
        Assert.AreEqual("arrow.clockwise", presentation.RefreshMacSymbolName);
        Assert.AreEqual("chevron.up", presentation.ExpandedChevronMacSymbolName);
        Assert.AreEqual("chevron.down", presentation.CollapsedChevronMacSymbolName);
        Assert.AreEqual("#A7B0BF", presentation.StrokeHex);
        Assert.AreEqual("Refresh thread inbox", presentation.RefreshHelp);
        Assert.AreEqual("Refresh thread inbox", presentation.RefreshAccessibilityLabel);
        Assert.AreEqual("Minimize", presentation.ExpandedCollapseHelp);
        Assert.AreEqual("Expand", presentation.CollapsedCollapseHelp);
        Assert.AreEqual("Minimize thread inbox", presentation.ExpandedCollapseAccessibilityLabel);
        Assert.AreEqual("Expand thread inbox", presentation.CollapsedCollapseAccessibilityLabel);
        Assert.AreEqual(17, presentation.HeaderIconWidth);
        Assert.AreEqual(15, presentation.HeaderIconHeight);
        Assert.AreEqual(1.25, presentation.StrokeThickness);
        Assert.AreEqual(15, presentation.ActionIconSize);
        Assert.AreEqual(1.3, presentation.ActionStrokeThickness);
    }
}
