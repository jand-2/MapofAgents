using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MentionSuggestionPanelPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacFloatingMentionMenuMetrics()
    {
        var presentation = MentionSuggestionPanelPresentation.Resolve();

        Assert.AreEqual(4, presentation.PanelPadding, 0.001);
        Assert.AreEqual(8, presentation.CornerRadius, 0.001);
        Assert.AreEqual(2, presentation.RowSpacing, 0.001);
        Assert.AreEqual(8, presentation.RowHorizontalPadding, 0.001);
        Assert.AreEqual(6, presentation.RowVerticalPadding, 0.001);
        Assert.AreEqual(18, presentation.IconWidth, 0.001);
        Assert.AreEqual(12, presentation.TitleFontSize, 0.001);
        Assert.AreEqual(10, presentation.SubtitleFontSize, 0.001);
        Assert.AreEqual(18, presentation.ShadowTranslationZ, 0.001);
    }

    [TestMethod]
    public void ForegroundColorsTrackMacMentionKindColors()
    {
        Assert.AreEqual("#0A84FF", MentionSuggestionPanelPresentation.ForegroundHexForKind("plugin"));
        Assert.AreEqual("#A7B0BF", MentionSuggestionPanelPresentation.ForegroundHexForKind("file"));
        Assert.AreEqual("#BF5AF2", MentionSuggestionPanelPresentation.ForegroundHexForKind("skill"));
        Assert.AreEqual("#FFD60A", MentionSuggestionPanelPresentation.ForegroundHexForKind("folder"));
        Assert.AreEqual("#30D158", MentionSuggestionPanelPresentation.ForegroundHexForKind("thread"));
        Assert.AreEqual("#30D158", MentionSuggestionPanelPresentation.ForegroundHexForKind("unknown"));
    }
}
