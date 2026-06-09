using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AttentionRailHeaderPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacExclamationBubbleTreatment()
    {
        var presentation = AttentionRailHeaderPresentation.Resolve();

        Assert.AreEqual("exclamationmark.bubble", presentation.MacSymbolName);
        Assert.AreEqual("#A7B0BF", presentation.StrokeHex);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(1.25, presentation.StrokeThickness);
        Assert.IsTrue(presentation.ExclamationLineTop < presentation.ExclamationLineBottom);
        Assert.AreEqual(1.4, presentation.ExclamationDotSize);
        Assert.AreEqual("Needs Attention", presentation.AccessibilityName);
    }
}
