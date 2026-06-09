using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadPopoverShellPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacNewThreadPopoverShell()
    {
        var presentation = NewThreadPopoverShellPresentation.Resolve();

        Assert.AreEqual(470, presentation.Width);
        Assert.AreEqual(620, presentation.Height);
        Assert.AreEqual("#24FFFFFF", presentation.BorderHex);
        Assert.AreEqual(1, presentation.BorderThickness, 0.001);
        Assert.AreEqual(8, presentation.CornerRadius, 0.001);
        Assert.AreEqual(18, presentation.ShadowTranslationZ, 0.001);
    }
}
