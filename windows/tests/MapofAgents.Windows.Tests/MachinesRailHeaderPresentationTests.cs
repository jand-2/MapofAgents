using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachinesRailHeaderPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacServerRackTreatment()
    {
        var presentation = MachinesRailHeaderPresentation.Resolve();

        Assert.AreEqual("server.rack", presentation.MacSymbolName);
        Assert.AreEqual("#A7B0BF", presentation.StrokeHex);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(2.5, presentation.UnitX);
        Assert.AreEqual(1.7, presentation.UnitTopInset);
        Assert.AreEqual(12, presentation.UnitWidth);
        Assert.AreEqual(3.6, presentation.UnitHeight);
        Assert.IsTrue(presentation.UnitGap > 0);
        Assert.AreEqual(1.2, presentation.StrokeThickness);
        Assert.AreEqual(1.15, presentation.IndicatorSize);
        Assert.AreEqual(1.75, presentation.IndicatorInsetX);
        Assert.AreEqual("Machines", presentation.AccessibilityName);
    }
}
