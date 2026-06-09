using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptFilteredEmptyStatePresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacFilteredTranscriptEmptyState()
    {
        var presentation = TranscriptFilteredEmptyStatePresentation.Resolve();

        Assert.AreEqual("No rows match the active filters", presentation.Title);
        Assert.AreEqual("Show All Rows", presentation.ButtonText);
        Assert.AreEqual("line.3.horizontal.decrease.circle", presentation.MacSymbolName);
        Assert.AreEqual("checklist", presentation.ButtonMacSymbolName);
        Assert.AreEqual(TranscriptFilterPresentation.ForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual("#12697586", presentation.BackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.BorderHex);
        Assert.AreEqual(18, presentation.Padding);
        Assert.AreEqual(10, presentation.ContentSpacing);
        Assert.AreEqual(8, presentation.CornerRadius);
        Assert.AreEqual(0, presentation.BorderThickness);
        Assert.AreEqual(TranscriptFilterPresentation.EmptyIconSize, presentation.IconSize);
        Assert.AreEqual(14, presentation.TitleFontSize);
        Assert.AreEqual(9, presentation.ButtonHorizontalPadding);
        Assert.AreEqual(4, presentation.ButtonVerticalPadding);
        Assert.AreEqual(6, presentation.ButtonContentSpacing);
        Assert.AreEqual(11, presentation.ButtonIconFontSize);
        Assert.AreEqual(12, presentation.ButtonTextFontSize);
    }
}
