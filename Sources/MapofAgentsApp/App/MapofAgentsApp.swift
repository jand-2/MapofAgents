import SwiftUI

@main
struct MapofAgentsApp: App {
    #if os(macOS)
    @State private var appSession = MapofAgentsAppSession()
    #endif

    var body: some Scene {
        #if os(macOS)
        Window("MapofAgents", id: "main") {
            RootView(session: appSession)
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
