using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarReadingPresentationTests
{
    [TestMethod]
    public void EmptyReaderUsesMacSplitRectangleTreatment()
    {
        var presentation = ToolbarReadingPresentation.Resolve(readingThreadCount: 0);

        Assert.AreEqual("rectangle.split.3x1", presentation.MacSymbolName);
        Assert.AreEqual("ToolbarButtonStyle", presentation.StyleKey);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("Open focused chat reading mode", presentation.ToolTip);
        Assert.AreEqual("Reader", presentation.Title);
        Assert.AreEqual(15, presentation.IconWidth);
        Assert.AreEqual(14, presentation.IconHeight);
        Assert.AreEqual(1, presentation.StrokeThickness);
    }

    [TestMethod]
    public void ReaderCountMatchesMacCommandBarTitle()
    {
        var presentation = ToolbarReadingPresentation.Resolve(readingThreadCount: 3);

        Assert.AreEqual("rectangle.split.3x1", presentation.MacSymbolName);
        Assert.AreEqual("Reader 3", presentation.Title);
    }
}
