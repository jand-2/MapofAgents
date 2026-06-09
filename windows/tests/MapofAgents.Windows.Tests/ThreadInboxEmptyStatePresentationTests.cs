using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxEmptyStatePresentationTests
{
    [TestMethod]
    public void ResolveUsesMacModeMessages()
    {
        Assert.AreEqual(
            "No active threads found.",
            ThreadInboxEmptyStatePresentation.Resolve("active", searchText: "").Message);
        Assert.AreEqual(
            "No finished threads found.",
            ThreadInboxEmptyStatePresentation.Resolve("finished", searchText: "").Message);
        Assert.AreEqual(
            "Nothing needs you right now.",
            ThreadInboxEmptyStatePresentation.Resolve("needsYou", searchText: "").Message);
        Assert.AreEqual(
            "No unread thread changes.",
            ThreadInboxEmptyStatePresentation.Resolve("unread", searchText: "").Message);
        Assert.AreEqual(
            "No known threads yet.",
            ThreadInboxEmptyStatePresentation.Resolve("recent", searchText: "").Message);
        Assert.AreEqual(
            "No archived threads loaded.",
            ThreadInboxEmptyStatePresentation.Resolve("archived", searchText: "").Message);
    }

    [TestMethod]
    public void SearchModePromptsBeforeQueryAndShowsNoMatchAfterQuery()
    {
        Assert.AreEqual(
            "Type to search known threads.",
            ThreadInboxEmptyStatePresentation.Resolve("search", searchText: "").Message);
        Assert.AreEqual(
            "No matching threads.",
            ThreadInboxEmptyStatePresentation.Resolve("search", searchText: "codex").Message);
    }

    [TestMethod]
    public void WorkflowFilterDoesNotOverrideMacEmptyMessage()
    {
        Assert.AreEqual(
            "No active threads found.",
            ThreadInboxEmptyStatePresentation.Resolve(
                "active",
                searchText: "",
                workflowFilter: "not-on-workflows").Message);
    }
}
