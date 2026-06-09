using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptErrorPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacTranscriptErrorBanner()
    {
        var presentation = TranscriptErrorPresentation.Resolve();

        Assert.AreEqual("Transcript unavailable", presentation.Title);
        Assert.AreEqual("exclamationmark.triangle.fill", presentation.MacSymbolName);
        Assert.AreEqual("\uE7BA", presentation.WindowsGlyph);
        Assert.AreEqual("#14FF453A", presentation.BackgroundHex);
        Assert.AreEqual("#33FF453A", presentation.BorderHex);
        Assert.AreEqual("#FF453A", presentation.IconForegroundHex);
        Assert.AreEqual("#F2F4F7", presentation.TitleForegroundHex);
        Assert.AreEqual("#A7B0BF", presentation.DetailForegroundHex);
        Assert.AreEqual("Retry", presentation.RetryLabel);
        Assert.AreEqual("Use Cached Transcript", presentation.UseCachedLabel);
        Assert.AreEqual(10, presentation.Padding, 0.001);
        Assert.AreEqual(8, presentation.CornerRadius, 0.001);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
        Assert.AreEqual(8, presentation.ContentSpacing, 0.001);
        Assert.AreEqual(8, presentation.HeaderColumnSpacing, 0.001);
        Assert.AreEqual(3, presentation.TextStackSpacing, 0.001);
        Assert.AreEqual(8, presentation.ActionSpacing, 0.001);
        Assert.AreEqual(1, presentation.IconTopMargin, 0.001);
        Assert.AreEqual(14, presentation.IconFontSize, 0.001);
        Assert.AreEqual(12, presentation.TitleFontSize, 0.001);
        Assert.AreEqual(12, presentation.DetailFontSize, 0.001);
        Assert.AreEqual(10, presentation.ButtonHorizontalPadding, 0.001);
        Assert.AreEqual(5, presentation.ButtonVerticalPadding, 0.001);
        Assert.AreEqual(12, presentation.ButtonFontSize, 0.001);
        Assert.AreEqual(4, presentation.DetailMaxLines);
    }
}
