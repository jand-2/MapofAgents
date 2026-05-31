import SwiftUI

@main
struct MapofAgentsApp: App {
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Connect to Codex") {
                    NotificationCenter.default.post(name: .mapofagentsConnectRequested, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        #else
        WindowGroup {
            IPhoneRootView()
        }
        #endif
    }
}

extension Notification.Name {
    static let mapofagentsConnectRequested = Notification.Name("mapofagentsConnectRequested")
}
