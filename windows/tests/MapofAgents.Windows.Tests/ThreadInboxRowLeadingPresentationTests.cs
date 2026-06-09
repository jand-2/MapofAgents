using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxRowLeadingPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacPairedBubbleThreadIcon()
    {
        var presentation = ThreadInboxRowLeadingPresentation.Resolve();

        Assert.AreEqual("bubble.left.and.bubble.right", presentation.ThreadMacSymbolName);
        Assert.AreEqual(18, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(1.15, presentation.StrokeThickness);
        Assert.AreEqual(0.72, presentation.BackBubbleOpacity);
    }
}
