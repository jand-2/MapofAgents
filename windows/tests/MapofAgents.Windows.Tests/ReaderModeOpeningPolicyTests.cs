using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderModeOpeningPolicyTests
{
    [TestMethod]
    public void OpeningEmptyReaderAddsSelectedThread()
    {
        var threadId = ReaderModeOpeningPolicy.ThreadToAddWhenOpening(
            isOpeningReader: true,
            existingReaderThreadCount: 0,
            selectedNodeId: "thread-a",
            selectedNodeIsThread: true);

        Assert.AreEqual("thread-a", threadId);
    }

    [TestMethod]
    public void OpeningEmptyReaderWithoutSelectedThreadLeavesReaderEmptyLikeMac()
    {
        var threadId = ReaderModeOpeningPolicy.ThreadToAddWhenOpening(
            isOpeningReader: true,
            existingReaderThreadCount: 0,
            selectedNodeId: null,
            selectedNodeIsThread: false);

        Assert.IsNull(threadId);
    }

    [TestMethod]
    public void OpeningReaderWithExistingThreadsDoesNotAddAnotherThread()
    {
        var threadId = ReaderModeOpeningPolicy.ThreadToAddWhenOpening(
            isOpeningReader: true,
            existingReaderThreadCount: 1,
            selectedNodeId: "thread-b",
            selectedNodeIsThread: true);

        Assert.IsNull(threadId);
    }

    [TestMethod]
    public void ClosingReaderDoesNotAddAThread()
    {
        var threadId = ReaderModeOpeningPolicy.ThreadToAddWhenOpening(
            isOpeningReader: false,
            existingReaderThreadCount: 0,
            selectedNodeId: "thread-c",
            selectedNodeIsThread: true);

        Assert.IsNull(threadId);
    }
}
