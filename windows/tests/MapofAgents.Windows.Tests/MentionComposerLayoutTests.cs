using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MentionComposerLayoutTests
{
    [TestMethod]
    public void EmptyDefaultComposerUsesMacTwoLineHeight()
    {
        var layout = MentionComposerLayout.Measure("");

        Assert.AreEqual(2, layout.VisibleLines);
        Assert.AreEqual(1, layout.EstimatedLines);
        Assert.AreEqual(60, layout.Height);
        Assert.AreEqual(60, layout.MinHeight);
        Assert.AreEqual(117, layout.MaxHeight);
    }

    [TestMethod]
    public void NewThreadComposerUsesMacFourToNineLineRange()
    {
        var layout = MentionComposerLayout.Measure(
            "Start this thread",
            MentionComposerLayout.NewThreadMinLines,
            MentionComposerLayout.NewThreadMaxLines);

        Assert.AreEqual(4, layout.VisibleLines);
        Assert.AreEqual(98, layout.Height);
        Assert.AreEqual(98, layout.MinHeight);
        Assert.AreEqual(193, layout.MaxHeight);
    }

    [TestMethod]
    public void ThreadReplyComposerUsesMacThreeToEightLineRange()
    {
        var layout = MentionComposerLayout.Measure(
            "Message this thread",
            MentionComposerLayout.ThreadReplyMinLines,
            MentionComposerLayout.ThreadReplyMaxLines);

        Assert.AreEqual(3, layout.VisibleLines);
        Assert.AreEqual(79, layout.Height);
        Assert.AreEqual(79, layout.MinHeight);
        Assert.AreEqual(174, layout.MaxHeight);
    }

    [TestMethod]
    public void LongComposerTextWrapsAtMacEstimatedColumnWidth()
    {
        var layout = MentionComposerLayout.Measure(
            new string('a', 109),
            MentionComposerLayout.NewThreadMinLines,
            MentionComposerLayout.NewThreadMaxLines);

        Assert.AreEqual(3, layout.EstimatedLines);
        Assert.AreEqual(4, layout.VisibleLines);
        Assert.AreEqual(98, layout.Height);
    }

    [TestMethod]
    public void ComposerHeightCapsAtMaximumLines()
    {
        var layout = MentionComposerLayout.Measure(
            string.Join('\n', Enumerable.Repeat("line", 12)),
            MentionComposerLayout.NewThreadMinLines,
            MentionComposerLayout.NewThreadMaxLines);

        Assert.AreEqual(12, layout.EstimatedLines);
        Assert.AreEqual(9, layout.VisibleLines);
        Assert.AreEqual(193, layout.Height);
    }
}
