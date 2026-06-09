using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderHeaderLayoutTests
{
    [TestMethod]
    public void MeasureUsesMacDesktopHeaderPaddingAndPickerWidth()
    {
        var layout = ReaderHeaderLayout.Measure(1180);

        Assert.AreEqual(14, layout.HorizontalPadding);
        Assert.AreEqual(12, layout.VerticalPadding);
        Assert.AreEqual(154, layout.RightPadding);
        Assert.AreEqual(10, layout.HeaderSpacing);
        Assert.AreEqual(13, layout.TitleFontSize);
        Assert.AreEqual("SemiBold", layout.TitleFontWeightName);
        Assert.IsTrue(layout.ShowsSummary);
        Assert.IsTrue(layout.ShowsAddLabel);
        Assert.AreEqual(260, layout.CandidateWidth);
        Assert.IsFalse(layout.UsesIconOnlyClearButton);
        Assert.AreEqual(8, layout.ClearButtonHorizontalPadding);
        Assert.AreEqual(3, layout.ClearButtonVerticalPadding);
        Assert.IsNull(layout.ClearButtonToolTip);
    }

    [TestMethod]
    public void MeasureKeepsSummaryButHidesAddLabelOnCompactWidths()
    {
        var layout = ReaderHeaderLayout.Measure(900);

        Assert.AreEqual(154, layout.RightPadding);
        Assert.IsTrue(layout.ShowsSummary);
        Assert.IsFalse(layout.ShowsAddLabel);
        Assert.AreEqual(210, layout.CandidateWidth);
        Assert.IsFalse(layout.UsesIconOnlyClearButton);
    }

    [TestMethod]
    public void MeasureProtectsTitleControlsAndUsesIconOnlyClearOnNarrowWidths()
    {
        var layout = ReaderHeaderLayout.Measure(620);

        Assert.AreEqual(92, layout.RightPadding);
        Assert.IsFalse(layout.ShowsSummary);
        Assert.IsFalse(layout.ShowsAddLabel);
        Assert.AreEqual(156, layout.CandidateWidth);
        Assert.IsTrue(layout.UsesIconOnlyClearButton);
        Assert.AreEqual(24, layout.ClearButtonWidth);
        Assert.AreEqual(24, layout.ClearButtonHeight);
        Assert.AreEqual(0, layout.ClearButtonHorizontalPadding);
        Assert.AreEqual(0, layout.ClearButtonVerticalPadding);
        Assert.AreEqual("Clear reader", layout.ClearButtonToolTip);
    }
}
