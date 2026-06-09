using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptToolRowPresentationTests
{
    [TestMethod]
    public void ResolveSplitsMacToolTitleBodyAndSummary()
    {
        var presentation = TranscriptToolRowPresentation.Resolve(
            "shell.exec\nstdout: built successfully\nstderr: none");

        Assert.AreEqual("shell.exec", presentation.Title);
        Assert.AreEqual("stdout: built successfully\nstderr: none", presentation.Body);
        Assert.AreEqual("stdout: built successfully", presentation.Summary);
        Assert.IsTrue(presentation.HasDetails);
        Assert.AreEqual(TranscriptToolRowPresentation.ShowDetailsLabel, presentation.ShowDetailsLabel);
        Assert.AreEqual(TranscriptToolRowPresentation.HideDetailsLabel, presentation.HideDetailsLabel);
    }

    [TestMethod]
    public void ResolveUsesSingleLineAsMacTitleAndBody()
    {
        var presentation = TranscriptToolRowPresentation.Resolve("tool result");

        Assert.AreEqual("tool result", presentation.Title);
        Assert.AreEqual("tool result", presentation.Body);
        Assert.AreEqual("tool result", presentation.Summary);
        Assert.IsTrue(presentation.HasDetails);
    }

    [TestMethod]
    public void ResolveFallsBackToNoDetailsForBlankRows()
    {
        var presentation = TranscriptToolRowPresentation.Resolve("   ");

        Assert.AreEqual(TranscriptToolRowPresentation.DefaultTitle, presentation.Title);
        Assert.AreEqual("", presentation.Body);
        Assert.AreEqual(TranscriptToolRowPresentation.NoDetailsSummary, presentation.Summary);
        Assert.IsFalse(presentation.HasDetails);
    }
}
