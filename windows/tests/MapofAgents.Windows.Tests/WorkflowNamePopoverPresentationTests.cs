using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class WorkflowNamePopoverPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacWorkflowNamePopoverShell()
    {
        var presentation = WorkflowNamePopoverPresentation.Resolve();

        Assert.AreEqual(340, presentation.Width);
        Assert.AreEqual(14, presentation.Padding);
        Assert.AreEqual("#24FFFFFF", presentation.BorderHex);
        Assert.AreEqual(1, presentation.BorderThickness);
        Assert.AreEqual(8, presentation.CornerRadius);
        Assert.AreEqual(18, presentation.ShadowTranslationZ);
    }

    [TestMethod]
    public void ResolveMatchesMacWorkflowNamePopoverContentRhythm()
    {
        var presentation = WorkflowNamePopoverPresentation.Resolve();

        Assert.AreEqual(14, presentation.SurfaceSpacing);
        Assert.AreEqual(10, presentation.HeaderSpacing);
        Assert.AreEqual(26, presentation.HeaderIconTileSize);
        Assert.AreEqual(6, presentation.HeaderIconCornerRadius);
        Assert.AreEqual(16, presentation.HeaderTitleFontSize);
        Assert.AreEqual(24, presentation.CloseButtonSize);
        Assert.AreEqual(12, presentation.CloseIconFontSize);
        Assert.AreEqual(8, presentation.ActionSpacing);
    }
}
