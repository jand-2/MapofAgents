using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class StatusStripLayoutTests
{
    [TestMethod]
    public void ResolveKeepsMacBottomLeadingOverlayInsetsAndPadding()
    {
        var layout = StatusStripLayout.Resolve();

        Assert.AreEqual(14, layout.EdgeInset);
        Assert.AreEqual(12, layout.HorizontalPadding);
        Assert.AreEqual(8, layout.VerticalPadding);
        Assert.AreEqual(8, layout.SurfaceCornerRadius);
    }

    [TestMethod]
    public void ResolveKeepsMacStatusStripSpacingAndDividers()
    {
        var layout = StatusStripLayout.Resolve();

        Assert.AreEqual(12, layout.GroupSpacing);
        Assert.AreEqual(6, layout.IconTextSpacing);
        Assert.AreEqual(1, layout.DividerWidth);
        Assert.AreEqual(16, layout.DividerHeight);
        Assert.AreEqual("#24FFFFFF", layout.DividerFillHex);
    }

    [TestMethod]
    public void ResolveKeepsMacCaptionTypographyAndErrorTreatment()
    {
        var layout = StatusStripLayout.Resolve();

        Assert.AreEqual(12, layout.FontSize);
        Assert.AreEqual(12, layout.IconFontSize);
        Assert.AreEqual(420, layout.ErrorMaxWidth);
        Assert.AreEqual(2, layout.ErrorMaxLines);
        Assert.IsTrue(layout.IsErrorTextSelectable);
    }

    [TestMethod]
    public void ResolveKeepsMacLocalConnectedFilledIconMetrics()
    {
        var layout = StatusStripLayout.Resolve();

        Assert.AreEqual(13, layout.LocalConnectedIconWidth);
        Assert.AreEqual(13, layout.LocalConnectedIconHeight);
        Assert.AreEqual(1.45, layout.LocalConnectedCheckStrokeThickness);
    }

    [TestMethod]
    public void ResolveKeepsMacRemoteAntennaIconMetrics()
    {
        var layout = StatusStripLayout.Resolve();

        Assert.AreEqual(16, layout.RemoteAntennaIconWidth);
        Assert.AreEqual(14, layout.RemoteAntennaIconHeight);
        Assert.AreEqual(1.15, layout.RemoteAntennaStrokeThickness);
    }
}
