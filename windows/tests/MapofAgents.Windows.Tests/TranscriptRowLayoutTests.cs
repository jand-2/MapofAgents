using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptRowLayoutTests
{
    [TestMethod]
    public void MeasureUsesMacTranscriptRowPaddingAndRadius()
    {
        var layout = TranscriptRowLayout.Measure();

        Assert.AreEqual(10, layout.Padding);
        Assert.AreEqual(8, layout.CornerRadius);
        Assert.AreEqual(4, layout.ContentSpacing);
    }
}
