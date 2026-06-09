using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxRowLayoutTests
{
    [TestMethod]
    public void MeasureUsesMacThreadInboxRowPadding()
    {
        var layout = ThreadInboxRowLayout.Measure();

        Assert.AreEqual(8, layout.HorizontalPadding);
        Assert.AreEqual(7, layout.VerticalPadding);
        Assert.AreEqual(8, layout.CornerRadius);
        Assert.AreEqual(7, layout.RowSpacing);
        Assert.AreEqual(8, layout.TopRowIconTextSpacing);
        Assert.AreEqual(6, layout.TopRowStatusMinSpacing);
        Assert.AreEqual(-2, layout.StatusBadgeLeadingInset);
        Assert.AreEqual(8, layout.ActionRowSpacing);
        Assert.AreEqual(11, layout.ActivityTimestampFontSize);
        Assert.AreEqual(1, layout.ActivityTimestampMaxLines);
        Assert.AreEqual(ThreadLiveStatePresentation.TertiaryHex, layout.ActivityTimestampForegroundHex);
        Assert.AreEqual(5, layout.PendingBadgeHorizontalPadding);
        Assert.AreEqual(1, layout.PendingBadgeVerticalPadding);
        Assert.AreEqual(8, layout.PendingBadgeCornerRadius);
        Assert.AreEqual(11, layout.PendingBadgeFontSize);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, layout.PendingBadgeForegroundHex);
        Assert.AreEqual("#24FF9F0A", layout.PendingBadgeBackgroundHex);
        Assert.AreEqual(5, layout.StatusBadgeHorizontalPadding);
        Assert.AreEqual(2, layout.StatusBadgeVerticalPadding);
        Assert.AreEqual(9, layout.StatusBadgeCornerRadius);
        Assert.AreEqual(11, layout.StatusBadgeFontSize);
    }
}
