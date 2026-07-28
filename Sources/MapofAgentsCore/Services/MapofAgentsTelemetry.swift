import Foundation
import OSLog

enum MapofAgentsTelemetry {
    static let subsystem = Bundle.main.bundleIdentifier ?? "dev.mapofagents.canvas"

    static let codexRuntime = Logger(
        subsystem: subsystem,
        category: "CodexRuntime"
    )

    static let persistence = Logger(
        subsystem: subsystem,
        category: "Persistence"
    )
}
