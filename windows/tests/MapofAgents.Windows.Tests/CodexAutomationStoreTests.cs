using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CodexAutomationStoreTests
{
    [TestMethod]
    public void LoadsHeartbeatAutomationsByThreadId()
    {
        var root = TemporaryCodexHome();
        WriteAutomation(
            root,
            "example-heartbeat",
            """
            version = 1
            id = "example-heartbeat"
            kind = "heartbeat"
            name = "Example heartbeat"
            prompt = "Keep this thread moving."
            status = "ACTIVE"
            rrule = "FREQ=MINUTELY;INTERVAL=30"
            target_thread_id = "thread-123"
            created_at = "2026-06-11T09:00:00Z"
            updated_at = "2026-06-11T09:10:00Z"
            """);

        var automations = new CodexAutomationStore(root).LoadAutomationsByThreadId();
        var automation = automations["thread-123"];

        Assert.AreEqual("example-heartbeat", automation.Id);
        Assert.IsTrue(automation.IsHeartbeat);
        Assert.IsTrue(automation.IsActive);
        Assert.AreEqual("Chat", automation.RunsInDisplayName);
        Assert.AreEqual("Every 30 minutes", automation.IntervalDisplayName);
    }

    [TestMethod]
    public void ScheduleComputesNextMinutelyRunFromAnchor()
    {
        var root = TemporaryCodexHome();
        WriteAutomation(
            root,
            "example-heartbeat",
            """
            version = 1
            id = "example-heartbeat"
            kind = "heartbeat"
            name = "Example heartbeat"
            prompt = "Keep this thread moving."
            status = "ACTIVE"
            rrule = "FREQ=MINUTELY;INTERVAL=30"
            target_thread_id = "thread-123"
            created_at = "2026-06-11T09:00:00Z"
            """);

        var automation = new CodexAutomationStore(root).LoadAutomations().Single();
        var reference = DateTimeOffset.Parse("2026-06-11T10:10:00Z");
        var expected = DateTimeOffset.Parse("2026-06-11T10:30:00Z");

        Assert.AreEqual(expected, automation.NextRun(reference));
    }

    [TestMethod]
    public void ScheduleAcceptsPrefixedRRule()
    {
        var schedule = new CodexAutomationSchedule("RRULE:FREQ=WEEKLY;BYHOUR=10;BYMINUTE=30;BYDAY=TH");

        Assert.AreEqual("Weekly", schedule.DisplayName);
    }

    [TestMethod]
    public void SavesEditableFieldsWithoutDroppingIdentity()
    {
        var root = TemporaryCodexHome();
        WriteAutomation(
            root,
            "example-heartbeat",
            """
            version = 1
            id = "example-heartbeat"
            kind = "heartbeat"
            name = "Example heartbeat"
            prompt = "Keep this thread moving."
            status = "ACTIVE"
            rrule = "FREQ=MINUTELY;INTERVAL=30"
            target_thread_id = "thread-123"
            created_at = "2026-06-11T09:00:00Z"
            updated_at = "2026-06-11T09:10:00Z"
            """);

        var store = new CodexAutomationStore(root);
        var saved = store.Save(new CodexAutomationEdit(
            "example-heartbeat",
            "Updated heartbeat",
            "Line one\nLine two",
            "paused",
            "FREQ=HOURLY;INTERVAL=2"));

        Assert.AreEqual("example-heartbeat", saved.Id);
        Assert.AreEqual("heartbeat", saved.Kind);
        Assert.AreEqual("Updated heartbeat", saved.Name);
        Assert.AreEqual("Line one\nLine two", saved.Prompt);
        Assert.AreEqual("PAUSED", saved.Status);
        Assert.AreEqual("FREQ=HOURLY;INTERVAL=2", saved.RRule);
        Assert.AreEqual("thread-123", saved.TargetThreadID);
        Assert.IsNull(saved.NextRun(DateTimeOffset.UtcNow));
    }

    [TestMethod]
    public void PreferredAutomationChoosesActiveThenNewest()
    {
        var olderActive = Summary("active-old", "ACTIVE", "2026-06-11T09:00:00Z");
        var newerPaused = Summary("paused-new", "PAUSED", "2026-06-11T10:00:00Z");
        var newestActive = Summary("active-new", "ACTIVE", "2026-06-11T11:00:00Z");

        Assert.AreEqual("active-old", CodexAutomationStore.PreferredAutomation(olderActive, newerPaused).Id);
        Assert.AreEqual("active-new", CodexAutomationStore.PreferredAutomation(olderActive, newestActive).Id);
    }

    private static string TemporaryCodexHome()
    {
        var root = Path.Combine(Path.GetTempPath(), $"mapofagents-automation-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }

    private static void WriteAutomation(string root, string id, string body)
    {
        var directory = Path.Combine(root, "automations", id);
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "automation.toml"), body);
    }

    private static CodexAutomationSummary Summary(string id, string status, string updatedAt)
    {
        return new CodexAutomationSummary(
            id,
            "heartbeat",
            id,
            "",
            status,
            "FREQ=HOURLY;INTERVAL=1",
            "thread-123",
            null,
            null,
            null,
            null,
            DateTimeOffset.Parse(updatedAt),
            null,
            "");
    }
}
