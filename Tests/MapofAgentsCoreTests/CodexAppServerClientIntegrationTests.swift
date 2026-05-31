import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func codexAppServerClientConnectsWhenIntegrationEnabled() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["MAPOFAGENTS_CODEX_INTEGRATION"] == "1"
        || environment["AGENTS3_CODEX_INTEGRATION"] == "1" else {
        return
    }

    let client = CodexAppServerClient()
    let initialize = try await client.request(
        method: "initialize",
        params: .object([
            "clientInfo": .object([
                "name": .string("mapofagents-tests"),
                "title": .string("mapofagents Tests"),
                "version": .string("0.1.0"),
            ]),
            "capabilities": .object([
                "experimentalApi": .bool(true),
            ]),
        ])
    )
    try await client.notify(method: "initialized")

    let models = try await client.request(
        method: "model/list",
        params: .object([
            "limit": .number(5),
            "includeHidden": .bool(false),
        ])
    )

    await client.stop()

    #expect(initialize["codexHome"]?.stringValue?.isEmpty == false)
    #expect((models["data"]?.arrayValue ?? []).isEmpty == false)
}
