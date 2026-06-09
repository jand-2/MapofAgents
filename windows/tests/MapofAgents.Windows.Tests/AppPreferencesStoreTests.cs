using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AppPreferencesStoreTests
{
    [TestMethod]
    public void LoadReturnsMacParityDefaultsWhenMissing()
    {
        var directory = TestDirectory();
        var store = new AppPreferencesStore(directory);

        var preferences = store.Load();

        Assert.IsTrue(preferences.ShowSubagents);
        Assert.IsFalse(preferences.NotifyOnCompleted);
        Assert.IsTrue(preferences.NotifyOnNeedsInput);
        Assert.IsTrue(preferences.NotifyOnFailed);
        Assert.IsFalse(preferences.ThreadInboxCollapsed);
        Assert.IsFalse(preferences.ActivityRailCollapsed);
        Assert.IsFalse(preferences.AttentionRailCollapsed);
        Assert.IsFalse(preferences.RuntimeDiagnosticsCollapsed);
    }

    [TestMethod]
    public void SaveRoundTripsPanelAndNotificationPreferences()
    {
        var directory = TestDirectory();
        var store = new AppPreferencesStore(directory);
        var saved = new AppPreferences
        {
            ShowSubagents = false,
            NotifyOnCompleted = true,
            NotifyOnNeedsInput = false,
            NotifyOnFailed = false,
            CodexRemotesCollapsed = true,
            TailnetCollapsed = true,
            ThreadInboxCollapsed = true,
            ActivityRailCollapsed = true,
            AttentionRailCollapsed = true,
            RuntimeDiagnosticsCollapsed = true
        };

        store.Save(saved);
        var loaded = store.Load();

        Assert.IsFalse(loaded.ShowSubagents);
        Assert.IsTrue(loaded.NotifyOnCompleted);
        Assert.IsFalse(loaded.NotifyOnNeedsInput);
        Assert.IsFalse(loaded.NotifyOnFailed);
        Assert.IsTrue(loaded.CodexRemotesCollapsed);
        Assert.IsTrue(loaded.TailnetCollapsed);
        Assert.IsTrue(loaded.ThreadInboxCollapsed);
        Assert.IsTrue(loaded.ActivityRailCollapsed);
        Assert.IsTrue(loaded.AttentionRailCollapsed);
        Assert.IsTrue(loaded.RuntimeDiagnosticsCollapsed);
    }

    [TestMethod]
    public void LoadFallsBackToDefaultsWhenPreferencesAreMalformed()
    {
        var directory = TestDirectory();
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "preferences.json"), "{ not json");

        var preferences = new AppPreferencesStore(directory).Load();

        Assert.IsTrue(preferences.ShowSubagents);
        Assert.IsFalse(preferences.NotifyOnCompleted);
        Assert.IsTrue(preferences.NotifyOnNeedsInput);
        Assert.IsTrue(preferences.NotifyOnFailed);
    }

    private static string TestDirectory()
    {
        return Path.Combine(Path.GetTempPath(), "mapofagents-preferences-tests", Guid.NewGuid().ToString("N"));
    }
}
