using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AttentionTranscriptRowPresentationTests
{
    [TestMethod]
    public void ResolveKeepsMacApprovalPillIdentity()
    {
        var presentation = AttentionTranscriptRowPresentation.Resolve();

        Assert.AreEqual("Approval", presentation.CategoryLabel);
        Assert.AreEqual("hand.raised", presentation.CategoryMacSymbolName);
        Assert.AreEqual("\uE7BA", presentation.CategoryWindowsGlyph);
        Assert.AreEqual(TranscriptCategoryPresentation.RedHex, presentation.BadgeForegroundHex);
        Assert.AreEqual("#1CFF453A", presentation.BadgeBackgroundHex);
    }

    [TestMethod]
    public void ResolveUsesMacAttentionCardChromeForTranscriptRows()
    {
        var presentation = AttentionTranscriptRowPresentation.Resolve();

        Assert.AreEqual(AttentionRequestCardPresentation.MacBackgroundHex, presentation.RowBackgroundHex);
        Assert.AreEqual(AttentionRequestCardPresentation.MacBorderHex, presentation.RowBorderHex);
        Assert.AreEqual(AttentionRequestCardPresentation.MacBorderThickness, presentation.RowBorderThickness);
    }

    [TestMethod]
    public void ResolveUsesMacFocusAffordanceText()
    {
        var presentation = AttentionTranscriptRowPresentation.Resolve();

        Assert.AreEqual("Open owning thread", presentation.FocusToolTip);
        Assert.AreEqual("Open owning thread", presentation.FocusAccessibilityName);
    }
}
