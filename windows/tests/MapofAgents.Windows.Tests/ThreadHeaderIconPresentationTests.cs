using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadHeaderIconPresentationTests
{
    [TestMethod]
    public void RegularThreadUsesMacPairedHeaderAndSingleKindBadgeSymbols()
    {
        var presentation = ThreadHeaderIconPresentation.Resolve(isSubagent: false);

        Assert.AreEqual("bubble.left.and.bubble.right", presentation.HeaderMacSymbolName);
        Assert.AreEqual("bubble.left", presentation.KindMacSymbolName);
        Assert.IsTrue(presentation.UsesHeaderThreadPairIcon);
        Assert.AreEqual(ThreadHeaderIconPresentation.ThreadGlyph, presentation.HeaderGlyph);
        Assert.AreEqual(ThreadHeaderIconPresentation.ThreadGlyph, presentation.KindGlyph);
        Assert.AreEqual(ThreadHeaderIconPresentation.BlueHex, presentation.HeaderForegroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.SecondaryHex, presentation.KindForegroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.ThreadHeaderBackgroundHex, presentation.HeaderBackgroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.ThreadKindBackgroundHex, presentation.KindBackgroundHex);
        Assert.AreEqual("#1F0A84FF", presentation.HeaderBackgroundHex);
        Assert.AreEqual("#1AA7B0BF", presentation.KindBackgroundHex);
        Assert.AreEqual(26, presentation.HeaderSurfaceSize);
        Assert.AreEqual(6, presentation.HeaderSurfaceCornerRadius);
        Assert.AreEqual(18, presentation.HeaderIconGridWidth);
        Assert.AreEqual(16, presentation.HeaderIconGridHeight);
        Assert.AreEqual(13, presentation.HeaderGlyphFontSize);
        Assert.AreEqual(11, presentation.HeaderPairBackGlyphFontSize);
        Assert.AreEqual(12, presentation.HeaderPairFrontGlyphFontSize);
        Assert.AreEqual(1.15, presentation.HeaderPairStrokeThickness, 0.001);
        Assert.AreEqual(0.72, presentation.HeaderPairBackOpacity, 0.001);
    }

    [TestMethod]
    public void SubagentUsesPeopleSymbolForHeaderAndKindBadge()
    {
        var presentation = ThreadHeaderIconPresentation.Resolve(isSubagent: true);

        Assert.AreEqual("person.2", presentation.HeaderMacSymbolName);
        Assert.AreEqual("person.2", presentation.KindMacSymbolName);
        Assert.IsFalse(presentation.UsesHeaderThreadPairIcon);
        Assert.AreEqual(ThreadHeaderIconPresentation.SubagentGlyph, presentation.HeaderGlyph);
        Assert.AreEqual(ThreadHeaderIconPresentation.SubagentGlyph, presentation.KindGlyph);
        Assert.AreEqual(ThreadHeaderIconPresentation.PurpleHex, presentation.HeaderForegroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.PurpleHex, presentation.KindForegroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.SubagentBackgroundHex, presentation.HeaderBackgroundHex);
        Assert.AreEqual(ThreadHeaderIconPresentation.SubagentKindBackgroundHex, presentation.KindBackgroundHex);
        Assert.AreEqual("#1FBF5AF2", presentation.HeaderBackgroundHex);
        Assert.AreEqual("#1ABF5AF2", presentation.KindBackgroundHex);
        Assert.AreEqual(26, presentation.HeaderSurfaceSize);
        Assert.AreEqual(6, presentation.HeaderSurfaceCornerRadius);
        Assert.AreEqual(13, presentation.HeaderGlyphFontSize);
        Assert.AreEqual(1.15, presentation.HeaderPairStrokeThickness, 0.001);
    }
}
