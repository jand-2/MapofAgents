using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadSendActionPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacFeedbackButtonTreatment()
    {
        var presentation = ThreadSendActionPresentation.Resolve();

        Assert.AreEqual("paperplane.fill", presentation.MacSymbolName);
        Assert.AreEqual("\uE724", presentation.WindowsGlyph);
        Assert.AreEqual(ThreadSendActionPresentation.PaperPlanePathData, presentation.PaperPlanePathData);
        Assert.AreEqual("#FFFFFFFF", presentation.IconFillHex);
        Assert.AreEqual(18, presentation.IconWidth);
        Assert.AreEqual(16, presentation.IconHeight);
        Assert.AreEqual(0.48, presentation.UnavailableOpacity, 0.001);
        Assert.AreEqual("Type a message or attach a file before sending.", presentation.MissingContentReason);
        Assert.AreEqual(
            "This thread is still running. Wait for the current turn to finish.",
            presentation.AwaitingResponseReason);
        Assert.AreEqual("This message is still being sent.", presentation.SubmittingReason);
        Assert.AreEqual("Send", presentation.ToolTip);
        Assert.AreEqual("Send message", presentation.AccessibilityName);
    }

    [TestMethod]
    public void AvailabilityMirrorsMacUnavailableReasons()
    {
        var running = ThreadSendActionPresentation.Availability(
            isAwaitingResponse: true,
            isSubmitting: false,
            draft: "hello",
            pendingAttachmentCount: 1);
        var submitting = ThreadSendActionPresentation.Availability(
            isAwaitingResponse: false,
            isSubmitting: true,
            draft: "hello",
            pendingAttachmentCount: 1);
        var empty = ThreadSendActionPresentation.Availability(
            isAwaitingResponse: false,
            isSubmitting: false,
            draft: "   ",
            pendingAttachmentCount: 0);
        var ready = ThreadSendActionPresentation.Availability(
            isAwaitingResponse: false,
            isSubmitting: false,
            draft: "hello",
            pendingAttachmentCount: 0);

        Assert.AreEqual(ThreadSendActionPresentation.AwaitingResponseReason, running.UnavailableReason);
        Assert.AreEqual(ThreadSendActionPresentation.UnavailableOpacity, running.Opacity, 0.001);
        Assert.AreEqual(ThreadSendActionPresentation.SubmittingReason, submitting.UnavailableReason);
        Assert.AreEqual(ThreadSendActionPresentation.MissingContentReason, empty.UnavailableReason);
        Assert.IsNull(ready.UnavailableReason);
        Assert.AreEqual(1.0, ready.Opacity, 0.001);
    }
}
