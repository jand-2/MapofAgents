namespace MapofAgents.Core;

public static class MachineDiscoveryAutoRefreshPolicy
{
    public static bool ShouldStartInitialDiscovery(
        bool hasRequestedInitialDiscovery,
        bool isReadingModePresented,
        bool isMachinesRailVisible,
        bool isMachinesRailCollapsed,
        bool isCodexDiscoveryRunning,
        bool isTailnetDiscoveryRunning)
    {
        return !hasRequestedInitialDiscovery &&
            !isReadingModePresented &&
            isMachinesRailVisible &&
            !isMachinesRailCollapsed &&
            !isCodexDiscoveryRunning &&
            !isTailnetDiscoveryRunning;
    }
}
