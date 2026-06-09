using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MessageRouteDeliveryPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacDeliveryColors()
    {
        Assert.AreEqual(ThreadInboxPresentation.BlueHex, MessageRouteDeliveryPresentation.Resolve(MessageRouteDeliveryStates.Pending).ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.GreenHex, MessageRouteDeliveryPresentation.Resolve(MessageRouteDeliveryStates.Delivered).ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.RedHex, MessageRouteDeliveryPresentation.Resolve(MessageRouteDeliveryStates.Failed).ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, MessageRouteDeliveryPresentation.Resolve(MessageRouteDeliveryStates.Unknown).ForegroundHex);
    }

    [TestMethod]
    public void ResolveNormalizesUnknownDeliveryState()
    {
        var presentation = MessageRouteDeliveryPresentation.Resolve(" mystery ");

        Assert.AreEqual("Unknown", presentation.Label);
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, presentation.ForegroundHex);
    }
}
