using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxWorkflowFilterLayoutTests
{
    [TestMethod]
    public void MeasureUsesMacSmallCaptionPickerMetrics()
    {
        var layout = ThreadInboxWorkflowFilterLayout.Measure();

        Assert.AreEqual(12, layout.FontSize);
        Assert.AreEqual(28, layout.Height);
        Assert.AreEqual(6, layout.CornerRadius);
        Assert.AreEqual(1, layout.BorderThickness);
        Assert.AreEqual(8, layout.HorizontalPadding);
        Assert.AreEqual(3, layout.VerticalPadding);
        Assert.AreEqual("#142A2C30", layout.BackgroundHex);
        Assert.AreEqual("#1F2A2C30", layout.PointerOverBackgroundHex);
        Assert.AreEqual("#292A2C30", layout.PressedBackgroundHex);
        Assert.AreEqual("#24FFFFFF", layout.BorderHex);
        Assert.AreEqual("#660A84FF", layout.FocusedBorderHex);
        Assert.AreEqual("#F2F4F7", layout.ForegroundHex);
        Assert.AreEqual("#A7B0BF", layout.ChevronForegroundHex);
    }
}
