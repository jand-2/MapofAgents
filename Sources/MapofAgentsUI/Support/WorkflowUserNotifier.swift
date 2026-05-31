import MapofAgentsCore
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

enum WorkflowUserNotifier {
    static func post(event: WorkflowEvent, threadTitle: String) async {
        #if canImport(UserNotifications)
        guard let content = notificationContent(for: event, threadTitle: threadTitle) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        guard await ensureAuthorization(center: center) else {
            return
        }

        let request = UNNotificationRequest(
            identifier: "mapofagents-\(event.id)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
        #endif
    }

    #if canImport(UserNotifications)
    private static func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }

        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    private static func notificationContent(for event: WorkflowEvent, threadTitle: String) -> UNMutableNotificationContent? {
        let content = UNMutableNotificationContent()
        switch event.kind {
        case .turnCompleted:
            content.title = "\(threadTitle) finished"
        case .threadCreated:
            return nil
        case .needsInput:
            content.title = "\(threadTitle) needs input"
        case .failed:
            content.title = "\(threadTitle) failed"
        case .turnStarted:
            return nil
        }

        content.body = event.summary
        content.sound = .default
        return content
    }
    #endif
}
