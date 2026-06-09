using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadPopoverLayoutTests
{
    [TestMethod]
    public void SizeMatchesMacDesktopPopoverBounds()
    {
        var size = ThreadPopoverLayout.Size(1380, 860);

        Assert.AreEqual(440, size.Width);
        Assert.AreEqual(560, size.Height);
    }

    [TestMethod]
    public void MeasurePlacesPopoverToRightWhenItFitsBeforeRailLane()
    {
        var frame = ThreadPopoverLayout.Measure(
            canvasWidth: 1380,
            canvasHeight: 860,
            nodePosition: new CanvasPoint(250, 200),
            nodeSize: CanvasSize.Thread,
            viewport: new CanvasViewport());

        Assert.AreEqual(374, frame.Left);
        Assert.AreEqual(276, frame.Top);
        Assert.AreEqual(440, frame.Width);
        Assert.AreEqual(560, frame.Height);
    }

    [TestMethod]
    public void MeasurePlacesPopoverToLeftWhenRightSideWouldOverlapRailLane()
    {
        var frame = ThreadPopoverLayout.Measure(
            canvasWidth: 1380,
            canvasHeight: 860,
            nodePosition: new CanvasPoint(650, 70),
            nodeSize: CanvasSize.Thread,
            viewport: new CanvasViewport());

        Assert.AreEqual(86, frame.Left);
        Assert.AreEqual(160, frame.Top);
    }

    [TestMethod]
    public void MeasureClampsSavedOffsetsInsideMacCanvasMargins()
    {
        var frame = ThreadPopoverLayout.Measure(
            canvasWidth: 1380,
            canvasHeight: 860,
            nodePosition: new CanvasPoint(650, 70),
            nodeSize: CanvasSize.Thread,
            viewport: new CanvasViewport(),
            savedOffset: new CanvasPoint(1200, 900));

        Assert.AreEqual(568, frame.Left);
        Assert.AreEqual(276, frame.Top);
    }

    [TestMethod]
    public void ClampFrameUsesSameRailReservedBoundsAsMeasurement()
    {
        var frame = ThreadPopoverLayout.ClampFrame(
            canvasWidth: 1380,
            canvasHeight: 860,
            width: 440,
            height: 560,
            left: 920,
            top: -120);

        Assert.AreEqual(568, frame.Left);
        Assert.AreEqual(24, frame.Top);
    }
}
