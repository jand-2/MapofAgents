using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarSearchPresentationTests
{
    [TestMethod]
    public void InactiveStateUsesMacMagnifyingGlassTreatment()
    {
        var presentation = ToolbarSearchPresentation.Resolve(isSearching: false);

        Assert.AreEqual("magnifyingglass", presentation.MacSymbolName);
        Assert.AreEqual("ToolbarPlainButtonStyle", presentation.StyleKey);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("Search the thread inbox", presentation.ToolTip);
        Assert.AreEqual(15, presentation.IconSize);
        Assert.AreEqual(1.55, presentation.StrokeThickness);
    }

    [TestMethod]
    public void SearchModeKeepsSearchCommandPlain()
    {
        var presentation = ToolbarSearchPresentation.Resolve(isSearching: true);

        Assert.AreEqual("magnifyingglass", presentation.MacSymbolName);
        Assert.AreEqual("ToolbarPlainButtonStyle", presentation.StyleKey);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("Search the thread inbox", presentation.ToolTip);
        Assert.AreEqual(15, presentation.IconSize);
        Assert.AreEqual(1.55, presentation.StrokeThickness);
    }
}
