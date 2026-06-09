using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadDefaultCwdResolverTests
{
    [TestMethod]
    public void DefaultCwdUsesParentOfWindowsCodexHome()
    {
        var machine = WindowsMachine(
            hostId: "remote-windows",
            codexHome: @"C:\Users\example\.codex");

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.CanonicalHostID, @"C:\Users\local");

        Assert.AreEqual(@"C:\Users\example", cwd);
    }

    [TestMethod]
    public void DefaultCwdUsesLocalDefaultDirectoryForLocalMachineWithoutCodexHome()
    {
        var machine = WindowsMachine(hostId: LocalHostIdentity.CanonicalHostID);

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.CanonicalHostID, @"C:\Users\example");

        Assert.AreEqual(@"C:\Users\example", cwd);
    }

    [TestMethod]
    public void DefaultCwdUsesLocalDefaultDirectoryForLegacyWindowsLocalMachine()
    {
        var machine = WindowsMachine(hostId: LocalHostIdentity.WindowsLegacyHostID);

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.WindowsLegacyHostID, @"C:\Users\example");

        Assert.AreEqual(@"C:\Users\example", cwd);
    }

    [TestMethod]
    public void DefaultCwdFallsBackToWindowsUserDirectoryForRemoteWindowsMachine()
    {
        var machine = WindowsMachine(hostId: "remote-windows");

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.CanonicalHostID, @"C:\Users\local");

        Assert.AreEqual(@"C:\Users\User", cwd);
    }

    [TestMethod]
    public void DefaultCwdReturnsNullForRemoteNonWindowsMachineWithoutCodexHome()
    {
        var machine = new CanvasNode
        {
            Kind = NodeKinds.Machine,
            Metadata = new NodeMetadata
            {
                HostID = "remote-mac",
                Platform = HostPlatforms.MacOS
            }
        };

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.CanonicalHostID, @"C:\Users\local");

        Assert.IsNull(cwd);
    }

    [TestMethod]
    public void DefaultCwdFallsBackWhenWindowsCodexHomeParentIsRoot()
    {
        var machine = WindowsMachine(
            hostId: LocalHostIdentity.CanonicalHostID,
            codexHome: @"C:\.codex");

        var cwd = ThreadDefaultCwdResolver.DefaultCwd(machine, LocalHostIdentity.CanonicalHostID, @"C:\Users\example");

        Assert.AreEqual(@"C:\Users\example", cwd);
    }

    [TestMethod]
    public void ParentDirectoryHandlesUnixStyleCodexHome()
    {
        var parent = ThreadDefaultCwdResolver.ParentDirectory(
            "/Users/example/.codex",
            HostPlatforms.MacOS);

        Assert.AreEqual("/Users/example", parent);
    }

    private static CanvasNode WindowsMachine(string hostId, string? codexHome = null)
    {
        return new CanvasNode
        {
            Kind = NodeKinds.Machine,
            Metadata = new NodeMetadata
            {
                HostID = hostId,
                Platform = HostPlatforms.Windows,
                CodexHome = codexHome
            }
        };
    }
}
