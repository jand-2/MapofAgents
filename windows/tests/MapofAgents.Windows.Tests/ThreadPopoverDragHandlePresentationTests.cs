using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadPopoverDragHandlePresentationTests
{
    [TestMethod]
    public void ResolveUsesMacLineHandleMetrics()
    {
        var presentation = ThreadPopoverDragHandlePresentation.Resolve();

        Assert.AreEqual("line.3.horizontal", presentation.MacSymbolName);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.ForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.HitTargetSize, presentation.HitTargetSize);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.IconWidth, presentation.IconWidth);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.IconHeight, presentation.IconHeight);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.LineWidth, presentation.LineWidth);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.LineHeight, presentation.LineHeight);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.LineRadius, presentation.LineRadius);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.TopLineOffset, presentation.TopLineOffset);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.MiddleLineOffset, presentation.MiddleLineOffset);
        Assert.AreEqual(ThreadPopoverDragHandlePresentation.BottomLineOffset, presentation.BottomLineOffset);
        Assert.AreEqual("Drag chat", presentation.ToolTip);
        Assert.AreEqual("Drag chat", presentation.AccessibilityName);
    }
}
