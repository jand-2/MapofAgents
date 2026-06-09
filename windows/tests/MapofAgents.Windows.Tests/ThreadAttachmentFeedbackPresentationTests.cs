using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadAttachmentFeedbackPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacInlineAttachmentErrorTreatment()
    {
        var presentation = ThreadAttachmentFeedbackPresentation.Resolve();

        Assert.AreEqual(
            "Clipboard does not contain a file or screenshot.",
            presentation.ClipboardUnavailableReason);
        Assert.AreEqual("#FF453A", presentation.ErrorForegroundHex);
        Assert.AreEqual(10, presentation.ErrorFontSize, 0.001);
        Assert.AreEqual(2, presentation.ErrorLineLimit);
        Assert.AreEqual("#A7B0BF", presentation.CountForegroundHex);
        Assert.AreEqual(10, presentation.CountFontSize, 0.001);
    }

    [TestMethod]
    public void CountTextMatchesMacAttachmentSummary()
    {
        Assert.AreEqual("", ThreadAttachmentFeedbackPresentation.CountText(0));
        Assert.AreEqual("1 attached", ThreadAttachmentFeedbackPresentation.CountText(1));
        Assert.AreEqual("2 attached", ThreadAttachmentFeedbackPresentation.CountText(2));
    }
}
