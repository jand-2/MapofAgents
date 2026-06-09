using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineDiscoveryAutoRefreshPolicyTests
{
    [TestMethod]
    public void StartsWhenMachinesRailFirstAppearsExpanded()
    {
        Assert.IsTrue(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: false,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: false));
    }

    [TestMethod]
    public void DoesNotStartWhenAlreadyRequestedOrBusy()
    {
        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: true,
            isReadingModePresented: false,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: false));

        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: false,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: true,
            isTailnetDiscoveryRunning: false));

        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: false,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: true));
    }

    [TestMethod]
    public void DoesNotStartWhenRailIsHiddenCollapsedOrReading()
    {
        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: true,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: false));

        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: false,
            isMachinesRailVisible: false,
            isMachinesRailCollapsed: false,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: false));

        Assert.IsFalse(MachineDiscoveryAutoRefreshPolicy.ShouldStartInitialDiscovery(
            hasRequestedInitialDiscovery: false,
            isReadingModePresented: false,
            isMachinesRailVisible: true,
            isMachinesRailCollapsed: true,
            isCodexDiscoveryRunning: false,
            isTailnetDiscoveryRunning: false));
    }
}
