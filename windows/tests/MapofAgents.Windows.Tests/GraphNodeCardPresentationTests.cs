using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class GraphNodeCardPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacNodeContainerMetrics()
    {
        var presentation = GraphNodeCardPresentation.Resolve();

        Assert.AreEqual(8, presentation.SurfaceCornerRadius);
        Assert.AreEqual(2, presentation.BorderWidth);
        Assert.AreEqual(3, presentation.SelectedBorderWidth);
        Assert.AreEqual(0, presentation.SelectedInnerStrokeWidth);
        Assert.AreEqual(10, presentation.HighlightCornerRadius);
        Assert.AreEqual(-5, presentation.HighlightInset);
        Assert.AreEqual(4, presentation.HighlightBorderWidth);
        Assert.AreEqual(10, presentation.HighlightShadowRadius);
        Assert.AreEqual(4, presentation.ShadowYOffset);
        Assert.AreEqual(6, presentation.DefaultShadowRadius);
        Assert.AreEqual(8, presentation.HoverShadowRadius);
        Assert.AreEqual(12, presentation.EmphasisShadowRadius);
        Assert.AreEqual(12, presentation.InnerPadding);
        Assert.AreEqual(10, presentation.InnerGap);
    }

    [TestMethod]
    public void ResolveMatchesMacNodeHeaderMetrics()
    {
        var presentation = GraphNodeCardPresentation.Resolve();

        Assert.AreEqual(9, presentation.HeadingGap);
        Assert.AreEqual(9, presentation.ActionGap);
        Assert.AreEqual(24, presentation.IconSize);
        Assert.AreEqual(6, presentation.IconCornerRadius);
        Assert.AreEqual(16, presentation.IconFontSize);
        Assert.AreEqual(6, presentation.TitleRowGap);
        Assert.AreEqual(14, presentation.TitleFontSize);
        Assert.AreEqual(3, presentation.SubtitleTopMargin);
        Assert.AreEqual(12, presentation.SubtitleFontSize);
    }

    [TestMethod]
    public void ResolveMatchesMacNodeFooterAndBadgeMetrics()
    {
        var presentation = GraphNodeCardPresentation.Resolve();

        Assert.AreEqual(18, presentation.AgentBadgeHeight);
        Assert.AreEqual(6, presentation.AgentBadgeHorizontalPadding);
        Assert.AreEqual(10, presentation.AgentBadgeFontSize);
        Assert.AreEqual(7, presentation.UnreadDotSize);
        Assert.AreEqual(6, presentation.FooterGap);
        Assert.AreEqual(20, presentation.FooterMinHeight);
        Assert.IsTrue(presentation.FooterSpacerBeforeMetadata);
        Assert.AreEqual(20, presentation.PillHeight);
        Assert.AreEqual(7, presentation.PillHorizontalPadding);
        Assert.AreEqual(11, presentation.PillFontSize);
        Assert.AreEqual(13, presentation.PillLineHeight);
        Assert.AreEqual(8, presentation.PillIconFontSize);
        Assert.AreEqual(11, presentation.PillSvgIconSize);
    }

    [TestMethod]
    public void WebMaterialUsesMacCanvasAndCardColorTokens()
    {
        var material = GraphNodeCardPresentation.WebMaterial();

        Assert.AreEqual("#1D1E20", material.CanvasBackgroundHex);
        Assert.AreEqual("#F2F4F7", material.PrimaryTextHex);
        Assert.AreEqual("#A7B0BF", material.SecondaryTextHex);
        Assert.AreEqual("#8F9BAA", material.TertiaryTextHex);
        Assert.AreEqual("rgba(33, 34, 37, 0.80)", material.SurfaceCss);
        Assert.AreEqual("rgba(33, 34, 37, 0.93)", material.StrongSurfaceCss);
        Assert.AreEqual("rgba(255, 255, 255, 0.18)", material.StrokeCss);
        Assert.AreEqual("rgba(255, 255, 255, 0.10)", material.SoftStrokeCss);
        Assert.AreEqual("rgba(0, 0, 0, 0.08)", material.DefaultShadowCss);
    }
}
