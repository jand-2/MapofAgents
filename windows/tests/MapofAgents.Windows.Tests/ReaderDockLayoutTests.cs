using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderDockLayoutTests
{
    [TestMethod]
    public void MeasureUsesSingleFullWidthTileForOneThread()
    {
        var layout = ReaderDockLayout.Measure(980, 720, 1);

        Assert.AreEqual(1, layout.ColumnCount);
        Assert.AreEqual(1, layout.RowCount);
        Assert.AreEqual(952, layout.TileWidth);
        Assert.AreEqual(692, layout.TileHeight);
        Assert.AreEqual(952, layout.SlotWidth);
        Assert.AreEqual(692, layout.SlotHeight);
    }

    [TestMethod]
    public void MeasureCapsReaderAtFourMacStyleColumns()
    {
        var layout = ReaderDockLayout.Measure(2100, 900, 7);

        Assert.AreEqual(4, layout.ColumnCount);
        Assert.AreEqual(2, layout.RowCount);
        Assert.IsTrue(layout.TileWidth >= ReaderDockLayout.MinimumColumnWidth);
        Assert.IsTrue(layout.TileHeight >= ReaderDockLayout.MinimumTileHeight);
    }

    [TestMethod]
    public void MeasureFallsBackToOneColumnWhenViewportIsNarrow()
    {
        var layout = ReaderDockLayout.Measure(390, 620, 3);

        Assert.AreEqual(1, layout.ColumnCount);
        Assert.AreEqual(3, layout.RowCount);
        Assert.AreEqual(ReaderDockLayout.MinimumColumnWidth, layout.TileWidth);
        Assert.AreEqual(ReaderDockLayout.MinimumTileHeight, layout.TileHeight);
    }

    [TestMethod]
    public void MeasureReservesInterTileSpacingForMultipleRowsAndColumns()
    {
        var layout = ReaderDockLayout.Measure(1326, 884, 6);

        Assert.AreEqual(3, layout.ColumnCount);
        Assert.AreEqual(2, layout.RowCount);
        Assert.AreEqual(430, layout.TileWidth);
        Assert.AreEqual(430, layout.TileHeight);
        Assert.AreEqual(442, layout.SlotWidth);
        Assert.AreEqual(442, layout.SlotHeight);
    }

    [TestMethod]
    public void MeasureDistributesOnlyInterRowSpacingLikeMacLazyGrid()
    {
        var layout = ReaderDockLayout.Measure(1326, 1200, 6);

        Assert.AreEqual(3, layout.ColumnCount);
        Assert.AreEqual(2, layout.RowCount);
        Assert.AreEqual(430, layout.TileWidth);
        Assert.AreEqual(580, layout.TileHeight);
        Assert.AreEqual(442, layout.SlotWidth);
        Assert.AreEqual(592, layout.SlotHeight);
    }
}
