using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MainWindowAsyncOwnershipTests
{
    [TestMethod]
    public void EventHandlersDoNotOwnUntrackedAsyncWork()
    {
        var source = File.ReadAllText(RepositoryFile(
            "windows",
            "src",
            "MapofAgents.Windows",
            "MainWindow.xaml.cs"));

        var asyncVoidHandlers = Regex.Matches(
                source,
                @"private\s+async\s+void\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(")
            .Select(match => match.Groups["name"].Value)
            .ToArray();

        CollectionAssert.AreEqual(
            new[] { "MainWindow_Closed" },
            asyncVoidHandlers,
            "Only the terminal close handler may remain async void; all other handlers must register work with the window lifetime coordinator.");
        Assert.IsFalse(source.Contains("+= async", StringComparison.Ordinal));
        Assert.IsFalse(source.Contains("DispatcherQueue.TryEnqueue(async", StringComparison.Ordinal));
    }

    [TestMethod]
    public void ConnectHandlerRegistersControllerFlowWithWindowLifetime()
    {
        var source = File.ReadAllText(RepositoryFile(
            "windows",
            "src",
            "MapofAgents.Windows",
            "MainWindow.xaml.cs"));

        Assert.IsTrue(
            Regex.IsMatch(
                source,
                @"private\s+void\s+ConnectButton_Click\s*\([^)]*\)\s*\{\s*RunWindowOperation\(ConnectFromFormAsync\);\s*\}",
                RegexOptions.Singleline),
            "ConnectButton_Click must lease its controller flow through RunWindowOperation.");
        StringAssert.Contains(
            source,
            "_appServerConnectionController.ConnectAsync(",
            "The leased handler must delegate connection lifecycle ownership to AppServerConnectionController.");
    }

    private static string RepositoryFile(params string[] segments)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(new[] { directory.FullName }.Concat(segments).ToArray());
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        Assert.Fail($"Could not locate repository file: {Path.Combine(segments)}");
        return "";
    }
}
