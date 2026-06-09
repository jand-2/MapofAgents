using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadFullAccessWarningPresentationTests
{
    [TestMethod]
    public void LocalWarningUsesMacYellowFullAccessNotice()
    {
        var warning = NewThreadFullAccessWarningPresentation.Resolve(isRemoteTarget: false);

        Assert.AreEqual(
            "Full Access disables filesystem sandboxing and can read or change files outside the selected folder.",
            warning.Text);
        Assert.AreEqual("exclamationmark.triangle.fill", warning.MacSymbolName);
        Assert.AreEqual("#FFD60A", warning.IconHex);
        Assert.AreEqual("#1F2128", warning.ExclamationHex);
        Assert.AreEqual("#1AFFD60A", warning.BackgroundHex);
        Assert.AreEqual("#00FFFFFF", warning.BorderHex);
        Assert.AreEqual(0, warning.BorderThickness);
        Assert.AreEqual(15, warning.IconWidth);
        Assert.AreEqual(14, warning.IconHeight);
        Assert.AreEqual(1.45, warning.ExclamationStrokeThickness);
    }

    [TestMethod]
    public void RemoteWarningNamesRemoteTargetRisk()
    {
        var warning = NewThreadFullAccessWarningPresentation.Resolve(isRemoteTarget: true);

        Assert.AreEqual(
            "Full Access disables filesystem sandboxing on the remote target and can read or change files outside the selected folder.",
            warning.Text);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.MacSymbolName, warning.MacSymbolName);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.IconHex, warning.IconHex);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.ExclamationHex, warning.ExclamationHex);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.BackgroundHex, warning.BackgroundHex);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.BorderHex, warning.BorderHex);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.BorderThickness, warning.BorderThickness);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.IconWidth, warning.IconWidth);
        Assert.AreEqual(NewThreadFullAccessWarningPresentation.IconHeight, warning.IconHeight);
        Assert.AreEqual(
            NewThreadFullAccessWarningPresentation.ExclamationStrokeThickness,
            warning.ExclamationStrokeThickness);
    }
}
