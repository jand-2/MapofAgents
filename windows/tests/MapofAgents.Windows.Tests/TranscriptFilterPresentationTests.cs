using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptFilterPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacDecreaseCircleFilterMetrics()
    {
        var presentation = TranscriptFilterPresentation.Resolve();

        Assert.AreEqual("line.3.horizontal.decrease.circle", presentation.MacSymbolName);
        Assert.AreEqual(TranscriptFilterPresentation.ForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual(TranscriptFilterPresentation.MutedForegroundHex, presentation.MutedForegroundHex);
        Assert.AreEqual(14, presentation.BarHorizontalPadding);
        Assert.AreEqual(7, presentation.BarVerticalPadding);
        Assert.AreEqual(8, presentation.BarColumnSpacing);
        Assert.AreEqual(7, presentation.ButtonHorizontalPadding);
        Assert.AreEqual(3, presentation.ButtonVerticalPadding);
        Assert.AreEqual(5, presentation.ButtonCornerRadius);
        Assert.AreEqual(6, presentation.ButtonContentSpacing);
        Assert.AreEqual(12, presentation.SummaryFontSize);
        Assert.AreEqual(11, presentation.DetailFontSize);
        Assert.AreEqual(18, presentation.ResetButtonSize);
        Assert.AreEqual(11, presentation.ResetIconFontSize);
        Assert.AreEqual(TranscriptFilterPresentation.IconSize, presentation.IconSize);
        Assert.AreEqual(TranscriptFilterPresentation.EmptyIconSize, presentation.EmptyIconSize);
        Assert.AreEqual(TranscriptFilterPresentation.StrokeThickness, presentation.StrokeThickness);
        Assert.AreEqual(TranscriptFilterPresentation.CircleInset, presentation.CircleInset);
        Assert.AreEqual(TranscriptFilterPresentation.TopLineWidth, presentation.TopLineWidth);
        Assert.AreEqual(TranscriptFilterPresentation.MiddleLineWidth, presentation.MiddleLineWidth);
        Assert.AreEqual(TranscriptFilterPresentation.BottomLineWidth, presentation.BottomLineWidth);
        Assert.IsTrue(presentation.TopLineWidth > presentation.MiddleLineWidth);
        Assert.IsTrue(presentation.MiddleLineWidth > presentation.BottomLineWidth);
        Assert.AreEqual("Filter transcript rows", presentation.ToolTip);
        Assert.AreEqual("Filter transcript rows", presentation.AccessibilityName);
    }

    [TestMethod]
    public void DetailForegroundUsesMacMutedTertiaryOnlyWhenShowingAllRows()
    {
        Assert.AreEqual(
            TranscriptFilterPresentation.MutedForegroundHex,
            TranscriptFilterPresentation.DetailForegroundHex(isShowingAllRows: true));
        Assert.AreEqual(
            TranscriptFilterPresentation.ForegroundHex,
            TranscriptFilterPresentation.DetailForegroundHex(isShowingAllRows: false));
    }
}
