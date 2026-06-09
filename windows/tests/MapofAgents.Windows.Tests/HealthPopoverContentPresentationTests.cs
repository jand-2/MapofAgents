using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class HealthPopoverContentPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPopoverHeaderAndSummaryDensity()
    {
        var presentation = HealthPopoverContentPresentation.Resolve();

        Assert.AreEqual(12, presentation.SurfacePadding);
        Assert.AreEqual(12, presentation.SurfaceSpacing);
        Assert.AreEqual(8, presentation.HeaderSpacing);
        Assert.AreEqual(26, presentation.HeaderIconSize);
        Assert.AreEqual(6, presentation.HeaderIconCornerRadius);
        Assert.AreEqual(13, presentation.HeaderIconFontSize);
        Assert.AreEqual(16, presentation.HeaderTitleFontSize);
        Assert.AreEqual(12, presentation.HeaderSubtitleFontSize);
        Assert.AreEqual(10, presentation.SummaryPadding);
        Assert.AreEqual(8, presentation.SummaryCornerRadius);
        Assert.AreEqual(3, presentation.SummaryStackSpacing);
    }

    [TestMethod]
    public void ResolveKeepsMacHealthGreenAccent()
    {
        var presentation = HealthPopoverContentPresentation.Resolve();

        Assert.AreEqual("#1A30D158", presentation.HeaderIconBackgroundHex);
        Assert.AreEqual("#30D158", presentation.HeaderIconForegroundHex);
        Assert.AreEqual("#1A30D158", presentation.SummaryBackgroundHex);
        Assert.AreEqual("#2630D158", presentation.SummaryBorderHex);
    }

    [TestMethod]
    public void ResolveUsesPlainMenuLikeActionRows()
    {
        var presentation = HealthPopoverContentPresentation.Resolve();

        Assert.AreEqual(8, presentation.ActionStackSpacing);
        Assert.AreEqual(28, presentation.ActionButtonMinHeight);
        Assert.AreEqual(6, presentation.ActionButtonCornerRadius);
        Assert.AreEqual(8, presentation.ActionButtonHorizontalPadding);
        Assert.AreEqual(3, presentation.ActionButtonVerticalPadding);
        Assert.AreEqual("#00FFFFFF", presentation.ActionButtonBackgroundHex);
        Assert.AreEqual("#D7DCE5", presentation.ActionButtonForegroundHex);
        Assert.AreEqual(7, presentation.ActionContentSpacing);
        Assert.AreEqual(16, presentation.ActionIconSize);
        Assert.AreEqual(13, presentation.ActionTextFontSize);
    }
}
