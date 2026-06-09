using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxRowKindPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacSingleBubbleThreadKindIcon()
    {
        var presentation = ThreadInboxRowKindPresentation.Resolve();

        Assert.AreEqual("bubble.left", presentation.ThreadMacSymbolName);
        Assert.AreEqual(14, presentation.IconWidth);
        Assert.AreEqual(12, presentation.IconHeight);
        Assert.AreEqual(1.1, presentation.StrokeThickness);
    }
}
