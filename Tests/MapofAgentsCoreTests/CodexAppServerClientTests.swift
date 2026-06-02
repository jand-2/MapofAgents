import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func turnStartUsesLongRunningRequestTimeout() {
    #expect(CodexAppServerClient.timeoutSeconds(for: "initialize") == 6)
    #expect(CodexAppServerClient.timeoutSeconds(for: "thread/turns/list") == 20)
    #expect(CodexAppServerClient.timeoutSeconds(for: "turn/start") == 1_800)
}

@Test
@MainActor
func daemonProxyErrorsAreExplicitlyFallbackEligible() {
    #expect(CodexAppServerError.daemonProxyHandshakeFailed("bad upgrade").isStdioFallbackEligible)
    #expect(CodexAppServerError.daemonProxyRequestTimedOut(method: "initialize").isStdioFallbackEligible)
    #expect(!CodexAppServerError.transport("Timed out waiting for initialize response from Codex App Server.").isStdioFallbackEligible)
    #expect(CodexRuntimeStore.shouldRetryConnectionWithFallback(after: CodexAppServerError.daemonProxyHandshakeFailed("bad upgrade")))
}

@Test
func jsonValueRejectsFractionalIntegerIDs() {
    #expect(JSONValue.number(7).intValue == 7)
    #expect(JSONValue.number(7.25).intValue == nil)
    #expect(JSONRPCRequestID(JSONValue.number(7)) == .int(7))
    #expect(JSONRPCRequestID(JSONValue.number(7.25)) == nil)
}

@Test
func endpointVerifierRejectsGenericCapabilitiesOnlyInitializeResults() {
    let genericResult: JSONValue = .object([
        "capabilities": .object([:]),
    ])
    let codexNamedResult: JSONValue = .object([
        "serverInfo": .object([
            "name": .string("Codex App Server"),
        ]),
        "capabilities": .object([:]),
    ])
    let platformResult: JSONValue = .object([
        "platformFamily": .string("macOS"),
        "capabilities": .object([:]),
    ])

    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(genericResult) == false)
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(codexNamedResult))
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(platformResult))
}

@Test
func endpointVerifierTrustsWindowsCodexRuntimeIdentityWithoutCapabilities() {
    let windowsCodexResult: JSONValue = .object([
        "userAgent": .string("mapofagents-ssh-verify/0.135.0 (Windows 10.0.26200; x86_64)"),
        "codexHome": .string("C:\\Users\\User\\.codex"),
        "platformFamily": .string("windows"),
        "platformOs": .string("windows"),
    ])
    let platformOnlyResult: JSONValue = .object([
        "platformFamily": .string("windows"),
    ])

    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(windowsCodexResult))
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(platformOnlyResult) == false)
}

@Test
func endpointVerifierUntrustedInitializeErrorListsResponseKeys() {
    let result: JSONValue = .object([
        "unexpected": .string("shape"),
        "platformFamily": .string("windows"),
    ])
    let error = AppServerEndpointVerificationError.untrustedInitializeResult(
        keys: AppServerEndpointVerifier.initializeResultKeys(result)
    )

    #expect(error.localizedDescription.contains("platformFamily"))
    #expect(error.localizedDescription.contains("unexpected"))
}

@Test
func appServerRelayEndpointRejectsInsecureRemotePolicies() throws {
    let loopback = try #require(URL(string: "ws://127.0.0.1:18945"))
    let remoteCleartext = try #require(URL(string: "ws://mac.lan:18945"))
    let remoteSecure = try #require(URL(string: "wss://mac.example.test:18945"))

    #expect(AppServerRelayEndpoint.connectionSecurityError(url: loopback, bearerToken: nil) == nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: loopback, bearerToken: "secret") == nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteSecure, bearerToken: "secret") == nil)

    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteCleartext, bearerToken: nil) != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteCleartext, bearerToken: "secret") != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteSecure, bearerToken: nil) != nil)
}

#if os(macOS)
@Test
func appServerClientRecordsInvalidJSONDiagnostics() async {
    let client = CodexAppServerClient()

    await client.ingestTestLine(Data("{not json".utf8))

    let diagnostics = await client.currentProtocolDiagnostics()
    #expect(diagnostics.first?.contains("Invalid JSON-RPC frame") == true)
}

@Test
func appServerClientRecordsUnsupportedResponseIDDiagnostics() async {
    let client = CodexAppServerClient()

    await client.ingestTestLine(Data(#"{"id":1.5,"result":null}"#.utf8))

    let diagnostics = await client.currentProtocolDiagnostics()
    #expect(diagnostics.first?.contains("Unsupported JSON-RPC response id") == true)
}
#endif
