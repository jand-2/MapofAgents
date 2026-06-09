using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TopNotificationPresentationTests
{
    [TestMethod]
    public void CompletedKindUsesMacActivityCompletionTreatment()
    {
        var presentation = TopNotificationPresentation.Resolve(
            "Background turn finished.",
            TopNotificationPresentation.CompletedKind);

        Assert.AreEqual("Turn completed", presentation.Title);
        Assert.AreEqual("Turn completed", presentation.Action);
        Assert.AreEqual("\uE73E", presentation.Glyph);
        Assert.AreEqual(TopNotificationPresentation.CheckmarkCircleFillIcon, presentation.IconKind);
        Assert.AreEqual("checkmark.circle.fill", presentation.MacSymbolName);
        Assert.AreEqual(TopNotificationPresentation.GreenHex, presentation.ForegroundHex);
        Assert.AreEqual(TopNotificationPresentation.SecondaryHex, presentation.MessageHex);
        Assert.AreEqual("#3830D158", presentation.BorderHex);
    }

    [TestMethod]
    public void NeedsInputKindUsesMacOrangeAttentionTreatment()
    {
        var presentation = TopNotificationPresentation.Resolve(
            "Approval requested.",
            TopNotificationPresentation.NeedsInputKind);

        Assert.AreEqual("Needs input", presentation.Title);
        Assert.AreEqual("Needs input", presentation.Action);
        Assert.AreEqual(TopNotificationPresentation.WarningTriangleGlyph, presentation.Glyph);
        Assert.AreEqual(TopNotificationPresentation.ExclamationBubbleFillIcon, presentation.IconKind);
        Assert.AreEqual("exclamationmark.bubble.fill", presentation.MacSymbolName);
        Assert.AreEqual(TopNotificationPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual(TopNotificationPresentation.SecondaryHex, presentation.MessageHex);
        Assert.AreEqual("#38FF9F0A", presentation.BorderHex);
    }

    [TestMethod]
    public void FailedKindUsesMacRedFailureTreatment()
    {
        var presentation = TopNotificationPresentation.Resolve(
            "Tool call did not return an error keyword.",
            TopNotificationPresentation.FailedKind);

        Assert.AreEqual("Action failed", presentation.Title);
        Assert.AreEqual("Failed", presentation.Action);
        Assert.AreEqual(TopNotificationPresentation.WarningTriangleGlyph, presentation.Glyph);
        Assert.AreEqual(TopNotificationPresentation.XmarkOctagonFillIcon, presentation.IconKind);
        Assert.AreEqual("xmark.octagon.fill", presentation.MacSymbolName);
        Assert.AreEqual(TopNotificationPresentation.RedHex, presentation.ForegroundHex);
        Assert.AreEqual(TopNotificationPresentation.RedHex, presentation.MessageHex);
        Assert.AreEqual("#38FF453A", presentation.BorderHex);
    }

    [TestMethod]
    public void GeneralConnectionMessageKeepsExistingConnectionTreatment()
    {
        var presentation = TopNotificationPresentation.Resolve(
            "Remote connected.",
            TopNotificationPresentation.GeneralKind);

        Assert.AreEqual("Connection updated", presentation.Title);
        Assert.AreEqual("Connection updated", presentation.Action);
        Assert.AreEqual("\uE930", presentation.Glyph);
        Assert.AreEqual(TopNotificationPresentation.FontGlyphIcon, presentation.IconKind);
        Assert.AreEqual("bell.badge", presentation.MacSymbolName);
        Assert.AreEqual(TopNotificationPresentation.GreenHex, presentation.ForegroundHex);
        Assert.AreEqual(TopNotificationPresentation.SecondaryHex, presentation.MessageHex);
        Assert.AreEqual("#3830D158", presentation.BorderHex);
    }
}
