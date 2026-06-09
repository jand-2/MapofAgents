using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadAttachmentTrayLayoutTests
{
    [TestMethod]
    public void MeasureMatchesMacSingleHorizontalAttachmentTray()
    {
        var layout = ThreadAttachmentTrayLayout.Measure();

        Assert.IsTrue(layout.UsesSingleHorizontalRow);
        Assert.AreEqual(8, layout.ItemSpacing, 0.001);
        Assert.AreEqual(0, layout.BottomPadding, 0.001);
    }
}
