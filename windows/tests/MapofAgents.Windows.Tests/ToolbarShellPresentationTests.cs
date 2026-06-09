using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarShellPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacCommandBarShell()
    {
        var presentation = ToolbarShellPresentation.Resolve();

        Assert.AreEqual(14, presentation.EdgeInset);
        Assert.AreEqual(10, presentation.Padding);
        Assert.AreEqual(8, presentation.CornerRadius);
        Assert.AreEqual(1240, presentation.MaxWidth);
        Assert.AreEqual(10, presentation.GroupSpacing);
        Assert.AreEqual(1, presentation.DividerWidth);
        Assert.AreEqual(20, presentation.DividerHeight);
        Assert.AreEqual("#24FFFFFF", presentation.DividerFillHex);
        Assert.AreEqual("#00FFFFFF", presentation.BorderHex);
        Assert.AreEqual(0, presentation.BorderThickness);
    }
}
