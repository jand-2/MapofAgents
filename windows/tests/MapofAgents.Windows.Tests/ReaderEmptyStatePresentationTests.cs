using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderEmptyStatePresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacReaderContentUnavailableView()
    {
        var presentation = ReaderEmptyStatePresentation.Resolve();

        Assert.AreEqual("No Chats Selected", presentation.Title);
        Assert.AreEqual(
            "Use the thread picker above to open chats from the active workflow.",
            presentation.Detail);
        Assert.AreEqual("bubble.left.and.bubble.right", presentation.MacSymbolName);
        Assert.AreEqual("\uE8F2", presentation.WindowsGlyph);
        Assert.AreEqual("#8F9BAA", presentation.IconStrokeHex);
        Assert.AreEqual("#F2F4F7", presentation.TitleForegroundHex);
        Assert.AreEqual("#A7B0BF", presentation.DetailForegroundHex);
        Assert.AreEqual(460, presentation.Width, 0.001);
        Assert.AreEqual(360, presentation.DetailMaxWidth, 0.001);
        Assert.AreEqual(10, presentation.StackSpacing, 0.001);
        Assert.AreEqual(48, presentation.IconWidth, 0.001);
        Assert.AreEqual(40, presentation.IconHeight, 0.001);
        Assert.AreEqual(2, presentation.IconStrokeThickness, 0.001);
        Assert.AreEqual(20, presentation.TitleFontSize, 0.001);
        Assert.AreEqual(12, presentation.DetailFontSize, 0.001);
    }
}
