using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class RuntimeDiagnosticsRailHeaderPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacStethoscopeTreatment()
    {
        var presentation = RuntimeDiagnosticsRailHeaderPresentation.Resolve();

        Assert.AreEqual("stethoscope", presentation.MacSymbolName);
        Assert.AreEqual("#A7B0BF", presentation.StrokeHex);
        Assert.AreEqual(17, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(1.25, presentation.StrokeThickness);
        Assert.AreEqual(1.4, presentation.EarTipSize);
        Assert.IsTrue(presentation.LeftEarTipX < presentation.RightEarTipX);
        Assert.AreEqual(1.8, presentation.EarTipY);
        Assert.AreEqual(3.4, presentation.ChestPieceSize);
        Assert.IsTrue(presentation.ChestPieceY > presentation.EarTipY);
        Assert.AreEqual("Runtime Diagnostic", presentation.AccessibilityName);
    }
}
