using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptLoadingRowPresentationTests
{
    [TestMethod]
    public void ResolveInitialLoadUsesMacCenteredBreathingRoom()
    {
        var presentation = TranscriptLoadingRowPresentation.Resolve(hasLoadedTranscript: false);

        Assert.IsTrue(presentation.IsInitialLoad);
        Assert.AreEqual(TranscriptLoadingRowPresentation.RegularPadding, presentation.Padding);
        Assert.AreEqual(TranscriptLoadingRowPresentation.InitialVerticalMargin, presentation.VerticalMargin);
        Assert.AreEqual(TranscriptLoadingRowPresentation.CenterAlignment, presentation.HorizontalAlignment);
        Assert.AreEqual(TranscriptLoadingRowPresentation.RegularBackgroundHex, presentation.BackgroundHex);
        Assert.AreEqual(TranscriptLoadingRowPresentation.RegularBorderHex, presentation.BorderHex);
        Assert.AreEqual(8, presentation.OuterColumnSpacing);
        Assert.AreEqual(18, presentation.ProgressRingSize);
        Assert.AreEqual(1, presentation.ProgressRingTopMargin);
        Assert.AreEqual(2, presentation.ContentSpacing);
        Assert.AreEqual(6, presentation.HeaderSpacing);
        Assert.AreEqual(12, presentation.LabelIconFontSize);
        Assert.AreEqual(13, presentation.TitleFontSize);
        Assert.AreEqual(11, presentation.DetailFontSize);
        Assert.AreEqual(2, presentation.DetailMaxLines);
    }

    [TestMethod]
    public void ResolveRefreshUsesMacCompactLeadingRow()
    {
        var presentation = TranscriptLoadingRowPresentation.Resolve(hasLoadedTranscript: true);

        Assert.IsFalse(presentation.IsInitialLoad);
        Assert.AreEqual(TranscriptLoadingRowPresentation.CompactPadding, presentation.Padding);
        Assert.AreEqual(TranscriptLoadingRowPresentation.CompactVerticalMargin, presentation.VerticalMargin);
        Assert.AreEqual(TranscriptLoadingRowPresentation.LeadingAlignment, presentation.HorizontalAlignment);
        Assert.AreEqual(TranscriptLoadingRowPresentation.CompactBackgroundHex, presentation.BackgroundHex);
        Assert.AreEqual(TranscriptLoadingRowPresentation.CompactBorderHex, presentation.BorderHex);
        Assert.AreEqual(8, presentation.OuterColumnSpacing);
        Assert.AreEqual(18, presentation.ProgressRingSize);
        Assert.AreEqual(1, presentation.ProgressRingTopMargin);
        Assert.AreEqual(2, presentation.ContentSpacing);
        Assert.AreEqual(6, presentation.HeaderSpacing);
        Assert.AreEqual(11, presentation.LabelIconFontSize);
        Assert.AreEqual(12, presentation.TitleFontSize);
        Assert.AreEqual(11, presentation.DetailFontSize);
        Assert.AreEqual(2, presentation.DetailMaxLines);
    }
}
