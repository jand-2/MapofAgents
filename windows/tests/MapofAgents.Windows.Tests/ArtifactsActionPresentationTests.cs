using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ArtifactsActionPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacShippingBoxMetrics()
    {
        var presentation = ArtifactsActionPresentation.Resolve();

        Assert.AreEqual("shippingbox", presentation.MacSymbolName);
        Assert.AreEqual(ArtifactsActionPresentation.ActionForegroundHex, presentation.ActionForegroundHex);
        Assert.AreEqual(ArtifactsActionPresentation.HeaderForegroundHex, presentation.HeaderForegroundHex);
        Assert.AreEqual(ArtifactsActionPresentation.EmptyForegroundHex, presentation.EmptyForegroundHex);
        Assert.AreEqual(ArtifactsActionPresentation.HitTargetSize, presentation.HitTargetSize);
        Assert.AreEqual(ArtifactsActionPresentation.ActionIconSize, presentation.ActionIconSize);
        Assert.AreEqual(ArtifactsActionPresentation.HeaderIconSize, presentation.HeaderIconSize);
        Assert.AreEqual(ArtifactsActionPresentation.EmptyIconSize, presentation.EmptyIconSize);
        Assert.AreEqual(ArtifactsActionPresentation.StrokeThickness, presentation.StrokeThickness);
        StringAssert.StartsWith(presentation.ShippingBoxPathData, "M2.2,5.1 L8,2.3");
        Assert.IsTrue(presentation.ShippingBoxPathData.Contains("M8,7.9 L8,14.9", StringComparison.Ordinal));
        Assert.AreEqual("This thread has not produced any artifacts yet.", presentation.UnavailableReason);
        Assert.AreEqual(0.48, presentation.UnavailableOpacity, 0.001);
        Assert.AreEqual("Artifacts", presentation.ToolTip);
        Assert.AreEqual("Artifacts", presentation.AccessibilityName);
    }
}
