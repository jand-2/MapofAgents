using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderDockChromePresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacReaderDockSurfaceAndTopHairline()
    {
        var presentation = ReaderDockChromePresentation.Resolve();

        Assert.AreEqual("#F51D1E20", presentation.BackgroundHex);
        Assert.AreEqual("#18FFFFFF", presentation.HairlineHex);
        Assert.AreEqual(1, presentation.HairlineThickness);
    }
}
