using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptTransientRowsTests
{
    [DataTestMethod]
    [DataRow(false, false, 0, 0, 0)]
    [DataRow(true, false, 1, 0, 1)]
    [DataRow(false, true, 0, 1, 1)]
    [DataRow(true, true, 1, 1, 2)]
    public void CountMatchesMacTransientTranscriptRowCategories(
        bool isLoadingTranscript,
        bool hasTranscriptError,
        int expectedProgressCount,
        int expectedSystemCount,
        int expectedTotalCount)
    {
        var counts = TranscriptTransientRows.Count(isLoadingTranscript, hasTranscriptError);

        Assert.AreEqual(expectedProgressCount, counts.ProgressCount);
        Assert.AreEqual(expectedSystemCount, counts.SystemCount);
        Assert.AreEqual(expectedTotalCount, counts.TotalCount);
    }
}
