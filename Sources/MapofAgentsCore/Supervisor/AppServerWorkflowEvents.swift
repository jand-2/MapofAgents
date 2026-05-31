import Foundation

public extension WorkflowEvent {
    static func appServerEvent(from notification: CodexServerNotification, hostID: HostID?) -> WorkflowEvent? {
        AppServerNotificationNormalizer.workflowEvent(from: notification, hostID: hostID)
    }
}

public enum SupervisorHostPlatformResolver {
    public static func platform(from value: String?) -> HostPlatform {
        let lowercased = (value ?? "").lowercased()
        if lowercased.contains("mac") || lowercased.contains("darwin") { return .macOS }
        if lowercased.contains("windows") { return .windows }
        if lowercased.contains("linux") { return .linux }
        if lowercased.contains("ipad") { return .iPadOS }
        if lowercased.contains("ios") { return .iOS }
        return .unknown
    }
}
