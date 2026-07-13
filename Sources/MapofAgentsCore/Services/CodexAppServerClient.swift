import Foundation

#if os(macOS)
import Darwin
#endif

public struct AppServerConnectionID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct CodexServerNotification: Sendable, Hashable {
    public var method: String
    public var params: JSONValue?
    public var requestID: JSONRPCRequestID?
    public var connectionID: AppServerConnectionID?

    public init(
        method: String,
        params: JSONValue?,
        requestID: JSONRPCRequestID? = nil,
        connectionID: AppServerConnectionID? = nil
    ) {
        self.method = method
        self.params = params
        self.requestID = requestID
        self.connectionID = connectionID
    }
}

public enum CodexAppServerError: Error, LocalizedError, Sendable {
    case unsupportedPlatform
    case codexNotInstalled
    case launchFailed(String)
    case disconnected
    case invalidResponse
    case daemonProxyHandshakeFailed(String)
    case daemonProxyRequestTimedOut(method: String)
    case ambiguousWrite(method: String)
    case staleServerRequest
    case server(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Codex App Server process management is only available on macOS in this build."
        case .codexNotInstalled:
            return "Could not find the codex executable in PATH."
        case .launchFailed(let message):
            return "Could not launch codex app-server: \(message)"
        case .disconnected:
            return "Codex App Server is disconnected."
        case .invalidResponse:
            return "Codex App Server returned an invalid response."
        case .daemonProxyHandshakeFailed(let message):
            return "Daemon proxy handshake failed: \(message)"
        case .daemonProxyRequestTimedOut(let method):
            return "Timed out waiting for \(method) response from daemon proxy Codex App Server."
        case .ambiguousWrite(let method):
            return "The connection ended before Codex confirmed \(method). The request was not replayed because it may already have completed; runtime state was refreshed before another attempt."
        case .staleServerRequest:
            return "This request belongs to an App Server connection that is no longer active."
        case .server(let message):
            return message
        case .transport(let message):
            return message
        }
    }
}

public extension CodexAppServerError {
    var isThreadNotFound: Bool {
        switch self {
        case .server(let message):
            return message.localizedCaseInsensitiveContains("thread not found")
        default:
            return false
        }
    }

    var isStdioFallbackEligible: Bool {
        switch self {
        case .daemonProxyHandshakeFailed, .daemonProxyRequestTimedOut:
            return true
        default:
            return false
        }
    }
}

public extension Error {
    var isCodexThreadNotFound: Bool {
        if let appServerError = self as? CodexAppServerError {
            return appServerError.isThreadNotFound
        }

        return localizedDescription.localizedCaseInsensitiveContains("thread not found")
    }
}

public actor CodexAppServerClient {
    private let session = AppServerSession()
    private var notificationHandler: (@Sendable (CodexServerNotification) -> Void)?
    private var launchDescription = "not started"
    private var daemonDiagnostic: String?
    private var protocolDiagnostics: [String] = []
    private var didInitialize = false

    #if os(macOS)
    private var framing: Framing = .jsonLines
    private var preferStdioFallbackUntil: Date?
    private var connectionID: AppServerConnectionID?
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    #endif

    public init() {}

    public func setNotificationHandler(_ handler: (@Sendable (CodexServerNotification) -> Void)?) {
        notificationHandler = handler
    }

    public func currentLaunchDescription() -> String {
        launchDescription
    }

    public func currentDaemonDiagnostic() -> String? {
        daemonDiagnostic
    }

    public func currentProtocolDiagnostics() -> [String] {
        protocolDiagnostics
    }

    public func isRunning() -> Bool {
        #if os(macOS)
        process?.isRunning == true
        #else
        false
        #endif
    }

    public func isInitializedAndRunning() -> Bool {
        #if os(macOS)
        didInitialize && process?.isRunning == true
        #else
        false
        #endif
    }

    public func currentConnectionID() -> AppServerConnectionID? {
        #if os(macOS)
        connectionID
        #else
        nil
        #endif
    }

    public func markInitialized() {
        didInitialize = true
    }

    public func start() throws {
        #if os(macOS)
        if process?.isRunning == true {
            return
        }

        invalidateConnection(terminate: false)

        guard let codexPath = LocalCodexDiscovery.findCodexExecutable() else {
            throw CodexAppServerError.codexNotInstalled
        }

        let launchMode = selectLaunchMode(codexPath: codexPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = launchMode.arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let connectionID = AppServerConnectionID()
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleProcessExit(connectionID: connectionID) }
        }

        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed(error.localizedDescription)
        }

        self.connectionID = connectionID
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.launchDescription = launchMode.description
        self.framing = launchMode.framing
        self.didInitialize = false
        self.stdoutBuffer.removeAll(keepingCapacity: true)

        if launchMode.framing == .webSocketFrames {
            do {
                let leftover = try performWebSocketHandshake(
                    input: stdinPipe.fileHandleForWriting,
                    output: stdoutPipe.fileHandleForReading
                )
                stdoutBuffer.append(leftover)
            } catch {
                preferStdioFallbackUntil = Date().addingTimeInterval(60)
                daemonDiagnostic = error.localizedDescription
                invalidateConnection(connectionID: connectionID, terminate: true)
                throw error
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data, connectionID: connectionID) }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await self?.appendProtocolDiagnostic(
                    Self.stderrDiagnostic(from: data),
                    connectionID: connectionID
                )
            }
        }

        if !stdoutBuffer.isEmpty {
            Task { [weak self] in
                await self?.ingest(Data(), connectionID: connectionID)
            }
        }
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    public func stop() {
        #if os(macOS)
        invalidateConnection(terminate: true)
        #endif
    }

    public func request(_ call: AppServerCall) async throws -> JSONValue {
        try start()
        #if os(macOS)
        guard let connectionID else { throw CodexAppServerError.disconnected }
        let timeoutContext: AppServerSessionTimeoutContext = framing == .webSocketFrames
            ? .localDaemonProxy
            : .localStdio
        do {
            return try await session.request(
                call,
                connectionID: connectionID,
                timeoutContext: timeoutContext
            ) { [weak self] message, expectedConnectionID in
                guard let self else { throw CodexAppServerError.disconnected }
                try await self.sendSessionMessage(message, connectionID: expectedConnectionID)
            }
        } catch {
            if self.connectionID == connectionID,
               framing == .webSocketFrames,
               Self.isSessionTimeout(error, method: call.method) {
                preferStdioFallbackUntil = Date().addingTimeInterval(60)
                if call.method == .initialize {
                    invalidateConnection(connectionID: connectionID, terminate: true)
                }
            }
            throw error
        }
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    public func readFile(path: String) async throws -> Data {
        let result = try await request(AppServerCall(
            .readFile,
            params: .object([
                "path": .string(path),
            ])
        ))
        return try Self.fileData(fromReadFileResponse: result)
    }

    public func createDirectory(path: String, recursive: Bool = true) async throws {
        _ = try await request(AppServerCall(
            .createDirectory,
            params: .object([
                "path": .string(path),
                "recursive": .bool(recursive),
            ])
        ))
    }

    public func writeFile(path: String, data: Data) async throws {
        _ = try await request(AppServerCall(
            .writeFile,
            params: .object([
                "path": .string(path),
                "dataBase64": .string(data.base64EncodedString()),
            ])
        ))
    }

    public static func fileData(fromReadFileResponse result: JSONValue) throws -> Data {
        guard let dataBase64 = result["dataBase64"]?.stringValue ?? result["data_base64"]?.stringValue,
              let data = Data(base64Encoded: dataBase64) else {
            throw CodexAppServerError.invalidResponse
        }
        return data
    }

    public func notify(method: String, params: JSONValue? = nil) throws {
        try start()
        var body: [String: JSONValue] = ["method": .string(method)]
        if let params {
            body["params"] = params
        }
        try writeMessage(.object(body))
    }

    public func respondToServerRequest(
        id: JSONRPCRequestID,
        result: JSONValue,
        connectionID expectedConnectionID: AppServerConnectionID
    ) throws {
        #if os(macOS)
        guard connectionID == expectedConnectionID,
              process?.isRunning == true,
              didInitialize,
              stdinPipe != nil else {
            throw CodexAppServerError.staleServerRequest
        }
        try writeMessage(.object([
            "id": id.jsonValue,
            "result": result,
        ]))
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    private func writeMessage(_ message: JSONValue) throws {
        #if os(macOS)
        guard let stdinPipe else {
            throw CodexAppServerError.disconnected
        }

        let payload = try JSONEncoder().encode(message)
        let data: Data
        switch framing {
        case .jsonLines:
            data = payload + Data([0x0A])
        case .webSocketFrames:
            data = Self.webSocketFrame(opcode: 0x1, payload: payload, masked: true)
        }
        try Self.writePipeData(data, to: stdinPipe.fileHandleForWriting)
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    private func sendSessionMessage(
        _ message: JSONValue,
        connectionID expectedConnectionID: AppServerConnectionID
    ) throws {
        #if os(macOS)
        guard connectionID == expectedConnectionID else {
            throw CodexAppServerError.disconnected
        }
        try writeMessage(message)
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private enum Framing {
        case jsonLines
        case webSocketFrames
    }

    private struct LaunchMode {
        var arguments: [String]
        var description: String
        var framing: Framing
    }

    private func selectLaunchMode(codexPath: String) -> LaunchMode {
        if let preferStdioFallbackUntil, preferStdioFallbackUntil > Date() {
            daemonDiagnostic = "Daemon proxy timed out recently; using stdio fallback for this session."
            return LaunchMode(
                arguments: ["app-server", "--listen", "stdio://"],
                description: "stdio app-server (daemon proxy fallback)",
                framing: .jsonLines
            )
        }

        preferStdioFallbackUntil = nil

        let startResult = runCodex(
            codexPath: codexPath,
            arguments: ["app-server", "daemon", "start"],
            timeout: 8
        )

        if startResult.exitCode == 0 {
            daemonDiagnostic = nil
            return LaunchMode(
                arguments: ["app-server", "proxy"],
                description: "daemon proxy",
                framing: .webSocketFrames
            )
        }

        daemonDiagnostic = startResult.combinedOutput.trimmedForDisplay
        return LaunchMode(
            arguments: ["app-server", "--listen", "stdio://"],
            description: "stdio app-server (daemon unavailable)",
            framing: .jsonLines
        )
    }

    private func runCodex(codexPath: String, arguments: [String], timeout: TimeInterval) -> ProcessResult {
        do {
            let result = try BoundedProcessRunner.runBlocking(
                executableURL: URL(fileURLWithPath: codexPath),
                arguments: arguments,
                timeout: timeout,
                maxOutputBytes: 1_048_576
            )
            let timedOut = result.terminationStatus == -1
            return ProcessResult(
                exitCode: result.terminationStatus,
                stdout: result.stdout.stringValue,
                stderr: timedOut
                    ? "Timed out running codex \(arguments.joined(separator: " "))."
                    : result.stderr.stringValue
            )
        } catch {
            return ProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }

    private func handleProcessExit(connectionID: AppServerConnectionID) {
        invalidateConnection(connectionID: connectionID, terminate: false)
    }

    private func invalidateConnection(
        connectionID expectedConnectionID: AppServerConnectionID? = nil,
        terminate: Bool
    ) {
        if let expectedConnectionID, connectionID != expectedConnectionID {
            return
        }

        let processToTerminate = process
        let invalidatedConnectionID = connectionID
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        connectionID = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        didInitialize = false
        stdoutBuffer.removeAll(keepingCapacity: true)
        if let invalidatedConnectionID {
            Task {
                await session.failPending(connectionID: invalidatedConnectionID)
            }
        }
        if terminate, processToTerminate?.isRunning == true {
            processToTerminate?.terminate()
        }
    }

    private static func isSessionTimeout(_ error: Error, method: AppServerMethod) -> Bool {
        switch error as? CodexAppServerError {
        case .daemonProxyRequestTimedOut:
            return true
        case .ambiguousWrite(let timedOutMethod):
            return timedOutMethod == method.rawValue
        default:
            return false
        }
    }

    private func performWebSocketHandshake(input: FileHandle, output: FileHandle) throws -> Data {
        let key = Self.webSocketKey()
        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ].joined(separator: "\r\n")

        let semaphore = DispatchSemaphore(value: 0)
        let state = HandshakeState()

        output.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if state.append(data) {
                semaphore.signal()
            }
        }

        try Self.writePipeData(Data(request.utf8), to: input)

        let result = semaphore.wait(timeout: .now() + 5)
        output.readabilityHandler = nil

        guard result == .success else {
            throw CodexAppServerError.daemonProxyHandshakeFailed("Timed out waiting for websocket upgrade response.")
        }

        let response = state.response()

        guard let headerRange = response.range(of: Data("\r\n\r\n".utf8)) else {
            throw CodexAppServerError.daemonProxyHandshakeFailed("Websocket upgrade response was incomplete.")
        }

        let headerData = response[..<headerRange.lowerBound]
        let header = String(data: headerData, encoding: .utf8) ?? ""
        guard header.contains(" 101 ") || header.hasPrefix("HTTP/1.1 101") || header.hasPrefix("HTTP/1.0 101") else {
            throw CodexAppServerError.daemonProxyHandshakeFailed(header.trimmedForDisplay)
        }

        let leftoverStart = headerRange.upperBound
        guard leftoverStart < response.endIndex else {
            return Data()
        }
        return Data(response[leftoverStart...])
    }

    private func ingest(_ data: Data, connectionID: AppServerConnectionID) async {
        guard self.connectionID == connectionID else { return }
        stdoutBuffer.append(data)
        guard stdoutBuffer.count <= Self.maximumInboundBufferBytes else {
            appendProtocolDiagnostic("Codex App Server exceeded the maximum inbound buffer size.")
            invalidateConnection(connectionID: connectionID, terminate: true)
            return
        }

        switch framing {
        case .jsonLines:
            await ingestJSONLines(connectionID: connectionID)
        case .webSocketFrames:
            await ingestWebSocketFrames(connectionID: connectionID)
        }
    }

    private func ingestJSONLines(connectionID: AppServerConnectionID) async {
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newlineIndex]
            stdoutBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            await handleLine(Data(line), connectionID: connectionID)
        }
    }

    private func ingestWebSocketFrames(connectionID: AppServerConnectionID) async {
        while let frame = nextWebSocketFrame() {
            switch frame.opcode {
            case 0x1:
                await handleLine(frame.payload, connectionID: connectionID)
            case 0x8:
                handleProcessExit(connectionID: connectionID)
            case 0x9:
                try? writeWebSocketFrame(opcode: 0xA, payload: frame.payload)
            case 0xA:
                continue
            default:
                continue
            }
        }
    }

    private struct WebSocketFrame {
        var opcode: UInt8
        var payload: Data
    }

    private func nextWebSocketFrame() -> WebSocketFrame? {
        let bytes = [UInt8](stdoutBuffer)
        guard bytes.count >= 2 else { return nil }

        let opcode = bytes[0] & 0x0F
        let masked = (bytes[1] & 0x80) != 0
        var length = UInt64(bytes[1] & 0x7F)
        var offset = 2

        if length == 126 {
            guard bytes.count >= 4 else { return nil }
            length = (UInt64(bytes[2]) << 8) | UInt64(bytes[3])
            offset = 4
        } else if length == 127 {
            guard bytes.count >= 10 else { return nil }
            length = 0
            for byte in bytes[2..<10] {
                length = (length << 8) | UInt64(byte)
            }
            offset = 10
        }

        var mask: [UInt8] = []
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            mask = Array(bytes[offset..<offset + 4])
            offset += 4
        }

        guard length <= UInt64(Int.max) else { return nil }
        let payloadLength = Int(length)
        let (frameLength, overflow) = offset.addingReportingOverflow(payloadLength)
        guard !overflow else { return nil }
        guard bytes.count >= frameLength else { return nil }

        var payload = Array(bytes[offset..<frameLength])
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }

        stdoutBuffer.removeFirst(frameLength)
        return WebSocketFrame(opcode: opcode, payload: Data(payload))
    }

    private func writeWebSocketFrame(opcode: UInt8, payload: Data) throws {
        guard let stdinPipe else {
            throw CodexAppServerError.disconnected
        }
        try Self.writePipeData(
            Self.webSocketFrame(opcode: opcode, payload: payload, masked: true),
            to: stdinPipe.fileHandleForWriting
        )
    }

    /// A closed child-process pipe normally raises SIGPIPE before Foundation can
    /// surface its throwing write error. Disable that signal for this descriptor
    /// so request sends fail through `AppServerSession`, which can classify an
    /// unacknowledged write as ambiguous and a read as disconnected.
    nonisolated static func writePipeData(_ data: Data, to handle: FileHandle) throws {
        let descriptor = handle.fileDescriptor
        guard descriptor >= 0,
              Darwin.fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw CodexAppServerError.disconnected
        }

        do {
            try handle.write(contentsOf: data)
        } catch {
            throw CodexAppServerError.disconnected
        }
    }

    private static func webSocketFrame(opcode: UInt8, payload: Data, masked: Bool) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode)

        let maskBit: UInt8 = masked ? 0x80 : 0
        if payload.count < 126 {
            frame.append(maskBit | UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            frame.append(maskBit | 126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        } else {
            frame.append(maskBit | 127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }

        if masked {
            let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
            frame.append(contentsOf: mask)
            let payloadBytes = [UInt8](payload)
            frame.append(contentsOf: payloadBytes.enumerated().map { index, byte in
                byte ^ mask[index % 4]
            })
        } else {
            frame.append(payload)
        }

        return frame
    }

    private static func webSocketKey() -> String {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
    }

    private func handleLine(_ data: Data, connectionID: AppServerConnectionID) async {
        switch await session.receive(data, connectionID: connectionID) {
        case .notification(let notification):
            notificationHandler?(notification)
        case .diagnostic(let diagnostic):
            appendProtocolDiagnostic(diagnostic)
        case nil:
            break
        }
    }

    func ingestTestLine(_ data: Data) async {
        let connectionID = self.connectionID ?? AppServerConnectionID()
        await handleLine(data, connectionID: connectionID)
    }

    private static func stderrDiagnostic(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<non-UTF8 stderr>"
        return "Codex App Server stderr: \(text.trimmedForDisplay)"
    }

    private func appendProtocolDiagnostic(
        _ diagnostic: String,
        connectionID expectedConnectionID: AppServerConnectionID? = nil
    ) {
        if let expectedConnectionID, connectionID != expectedConnectionID {
            return
        }
        let trimmed = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        protocolDiagnostics.insert(trimmed, at: 0)
        if protocolDiagnostics.count > 20 {
            protocolDiagnostics.removeLast(protocolDiagnostics.count - 20)
        }
    }

    private static let maximumInboundBufferBytes = 32 * 1_024 * 1_024
    #endif
}

#if os(macOS)
private struct ProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private final class HandshakeState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var didFindHeader = false

    func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        guard !didFindHeader, buffer.range(of: Data("\r\n\r\n".utf8)) != nil else {
            return false
        }

        didFindHeader = true
        return true
    }

    func response() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

private extension String {
    var trimmedForDisplay: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 220 else { return trimmed }
        return String(trimmed.prefix(217)) + "..."
    }
}
#endif
