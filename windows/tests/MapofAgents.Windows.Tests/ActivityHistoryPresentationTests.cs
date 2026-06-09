using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ActivityHistoryPresentationTests
{
    [TestMethod]
    public void UsesMacActivityHistoryPopoverMetrics()
    {
        var presentation = ActivityHistoryPresentation.Resolve();

        Assert.AreEqual(380, presentation.Width);
        Assert.AreEqual(420, presentation.MaxListHeight);
        Assert.AreEqual("headline", presentation.HeaderMacFontStyleName);
        Assert.AreEqual(10, presentation.SurfaceSpacing);
        Assert.AreEqual(13, presentation.HeaderTitleFontSize);
        Assert.AreEqual(8, presentation.HeaderIconSpacing);
        Assert.AreEqual(8, presentation.HeaderActionSpacing);
        Assert.AreEqual(12, presentation.DismissCurrentFontSize);
        Assert.AreEqual(22, presentation.CloseButtonSize);
        Assert.AreEqual(12, presentation.CloseIconFontSize);
        Assert.AreEqual(12, presentation.EmptyFontSize);
        Assert.AreEqual(10, presentation.EmptyVerticalPadding);
        Assert.AreEqual(8, presentation.RowSpacing);
        Assert.AreEqual(8, presentation.RowBottomGap);
        Assert.AreEqual(8, presentation.RowPadding);
        Assert.AreEqual(9, presentation.RowColumnSpacing);
        Assert.AreEqual(16, presentation.RowIconColumnWidth);
        Assert.AreEqual(13, presentation.RowIconFontSize);
        Assert.AreEqual(3, presentation.RowContentSpacing);
        Assert.AreEqual(6, presentation.RowTitleTimeSpacing);
        Assert.AreEqual(12, presentation.RowTitleFontSize);
        Assert.AreEqual(11, presentation.RowTimeFontSize);
        Assert.AreEqual(12, presentation.RowMessageFontSize);
        Assert.AreEqual(11, presentation.RowActionFontSize);
        Assert.AreEqual(0, presentation.RowBorderThickness);
        Assert.AreEqual("No notifications yet.", presentation.EmptyMessage);
        Assert.AreEqual("Dismiss Current", presentation.DismissCurrentLabel);
    }

    [TestMethod]
    public void HidesPopoverNotificationPreferencesButtonLikeMac()
    {
        var presentation = ActivityHistoryPresentation.Resolve();

        Assert.IsFalse(presentation.ShowsNotificationPreferencesButton);
    }
}
