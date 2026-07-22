import Foundation

#if os(macOS)
import Darwin
#endif

public struct WorkflowMessageRelayRequest: Codable, Hashable, Sendable {
    public var requestID: String
    public var sourceProvider: AgentProvider
    public var sourceHostID: HostID
    public var sourceThreadID: String
    public var targetProvider: AgentProvider
    public var targetHostID: HostID
    public var targetThreadID: String
    public var message: String
    public var createdAtEpochSeconds: TimeInterval

    public init(
        requestID: String = UUID().uuidString.lowercased(),
        sourceProvider: AgentProvider,
        sourceHostID: HostID,
        sourceThreadID: String,
        targetProvider: AgentProvider,
        targetHostID: HostID,
        targetThreadID: String,
        message: String,
        createdAtEpochSeconds: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.requestID = requestID
        self.sourceProvider = sourceProvider
        self.sourceHostID = sourceHostID
        self.sourceThreadID = sourceThreadID
        self.targetProvider = targetProvider
        self.targetHostID = targetHostID
        self.targetThreadID = targetThreadID
        self.message = message
        self.createdAtEpochSeconds = createdAtEpochSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case requestID
        case sourceProvider
        case sourceHostID
        case sourceThreadID
        case targetProvider
        case targetHostID
        case targetThreadID
        case message
        case createdAtEpochSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        sourceProvider = try container.decode(AgentProvider.self, forKey: .sourceProvider)
        sourceHostID = HostID(rawValue: try container.decode(String.self, forKey: .sourceHostID))
        sourceThreadID = try container.decode(String.self, forKey: .sourceThreadID)
        targetProvider = try container.decode(AgentProvider.self, forKey: .targetProvider)
        targetHostID = HostID(rawValue: try container.decode(String.self, forKey: .targetHostID))
        targetThreadID = try container.decode(String.self, forKey: .targetThreadID)
        message = try container.decode(String.self, forKey: .message)
        createdAtEpochSeconds = try container.decode(TimeInterval.self, forKey: .createdAtEpochSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(sourceProvider, forKey: .sourceProvider)
        try container.encode(sourceHostID.rawValue, forKey: .sourceHostID)
        try container.encode(sourceThreadID, forKey: .sourceThreadID)
        try container.encode(targetProvider, forKey: .targetProvider)
        try container.encode(targetHostID.rawValue, forKey: .targetHostID)
        try container.encode(targetThreadID, forKey: .targetThreadID)
        try container.encode(message, forKey: .message)
        try container.encode(createdAtEpochSeconds, forKey: .createdAtEpochSeconds)
    }
}

public struct WorkflowMessageRelayResult: Codable, Hashable, Sendable {
    public var requestID: String
    public var success: Bool
    public var detail: String
    public var reply: String?

    public init(
        requestID: String,
        success: Bool,
        detail: String,
        reply: String? = nil
    ) {
        self.requestID = requestID
        self.success = success
        self.detail = detail
        self.reply = reply
    }
}

public enum WorkflowMessageFileRelayError: LocalizedError, Sendable {
    case unsupportedPlatform
    case insecureDirectory(String)
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "The workflow message relay is only available in the macOS app."
        case .insecureDirectory(let path):
            return "The workflow message relay refused an insecure directory at \(path)."
        case .invalidRequest(let detail):
            return "The workflow message relay rejected a request: \(detail)"
        }
    }
}

/// A local, app-owned bridge between provider CLI sessions on the active canvas.
///
/// The helper writes a request into a user-private queue and waits for an
/// app-authored result. Requests are claimed before delivery. An abandoned
/// claim is failed on restart rather than replayed, because provider turns are
/// not idempotent.
public final class WorkflowMessageFileRelay: @unchecked Sendable {
    public static let maximumMessageBytes = 64 * 1_024
    public static let maximumRequestBytes = 96 * 1_024
    public static let maximumRequestAge: TimeInterval = 5 * 60

    public let rootDirectoryURL: URL
    public let pendingDirectoryURL: URL
    public let claimedDirectoryURL: URL
    public let resultsDirectoryURL: URL
    public let helperExecutableURL: URL

    private let pollInterval: Duration

    public init(
        rootDirectoryURL: URL = WorkflowMessageFileRelay.defaultRootDirectoryURL,
        pollInterval: Duration = .milliseconds(350)
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.pendingDirectoryURL = rootDirectoryURL.appendingPathComponent("pending", isDirectory: true)
        self.claimedDirectoryURL = rootDirectoryURL.appendingPathComponent("claimed", isDirectory: true)
        self.resultsDirectoryURL = rootDirectoryURL.appendingPathComponent("results", isDirectory: true)
        self.helperExecutableURL = rootDirectoryURL.appendingPathComponent("send-message", isDirectory: false)
        self.pollInterval = pollInterval
    }

    public static var defaultRootDirectoryURL: URL {
        #if os(macOS)
        URL(fileURLWithPath: "/tmp/mapofagents-workflow-\(getuid())", isDirectory: true)
        #else
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mapofagents-workflow", isDirectory: true)
        #endif
    }

    public static var defaultHelperExecutableURL: URL {
        defaultRootDirectoryURL.appendingPathComponent("send-message", isDirectory: false)
    }

    public func start(
        onRequest: @escaping @MainActor @Sendable (WorkflowMessageRelayRequest) async -> WorkflowMessageRelayResult
    ) throws -> Task<Void, Never> {
        #if os(macOS)
        try prepareQueue()
        try failAbandonedClaims()
        return Task.detached(priority: .utility) { [self] in
            while !Task.isCancelled {
                await processPendingRequests(onRequest: onRequest)
                do {
                    try await Task.sleep(for: pollInterval)
                } catch {
                    return
                }
            }
        }
        #else
        throw WorkflowMessageFileRelayError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func prepareQueue() throws {
        try ensurePrivateDirectory(rootDirectoryURL)
        try ensurePrivateDirectory(pendingDirectoryURL)
        try ensurePrivateDirectory(claimedDirectoryURL)
        try ensurePrivateDirectory(resultsDirectoryURL)
        pruneStaleResults()
        try MapofAgentsPrivateFile.write(Data(Self.helperScript.utf8), to: helperExecutableURL)
        guard chmod(helperExecutableURL.path, mode_t(0o700)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        var status = stat()
        if lstat(url.path, &status) == 0 {
            guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  status.st_uid == getuid(),
                  (status.st_mode & mode_t(0o077)) == 0 else {
                throw WorkflowMessageFileRelayError.insecureDirectory(url.path)
            }
            guard chmod(url.path, mode_t(0o700)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return
        }

        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        guard chmod(url.path, mode_t(0o700)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func processPendingRequests(
        onRequest: @escaping @MainActor @Sendable (WorkflowMessageRelayRequest) async -> WorkflowMessageRelayResult
    ) async {
        let pendingURLs = queueFiles(in: pendingDirectoryURL)
        for pendingURL in pendingURLs where !Task.isCancelled {
            let claimedURL = claimedDirectoryURL.appendingPathComponent(pendingURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: pendingURL, to: claimedURL)
            } catch {
                continue
            }

            let result: WorkflowMessageRelayResult
            do {
                let request = try decodeRequest(at: claimedURL)
                result = await onRequest(request)
            } catch {
                let requestID = claimedURL.deletingPathExtension().lastPathComponent
                result = WorkflowMessageRelayResult(
                    requestID: requestID,
                    success: false,
                    detail: error.localizedDescription
                )
            }
            write(result: result, removingClaimAt: claimedURL)
        }
    }

    private func failAbandonedClaims() throws {
        for claimedURL in queueFiles(in: claimedDirectoryURL) {
            let requestID = claimedURL.deletingPathExtension().lastPathComponent
            let result = WorkflowMessageRelayResult(
                requestID: requestID,
                success: false,
                detail: "A prior delivery was interrupted after it was claimed. Its outcome is unknown, so MapofAgents did not replay the message."
            )
            write(result: result, removingClaimAt: claimedURL)
        }
    }

    private func decodeRequest(at url: URL) throws -> WorkflowMessageRelayRequest {
        let data = try MapofAgentsPrivateFile.read(url, maximumBytes: Self.maximumRequestBytes)
        let request = try JSONDecoder().decode(WorkflowMessageRelayRequest.self, from: data)
        let expectedID = url.deletingPathExtension().lastPathComponent
        guard request.requestID == expectedID,
              UUID(uuidString: request.requestID) != nil else {
            throw WorkflowMessageFileRelayError.invalidRequest("requestID does not match its queue filename")
        }
        guard request.sourceThreadID.utf8.count <= 512,
              request.targetThreadID.utf8.count <= 512,
              request.sourceHostID.rawValue.utf8.count <= 256,
              request.targetHostID.rawValue.utf8.count <= 256 else {
            throw WorkflowMessageFileRelayError.invalidRequest("a host or thread identifier is too long")
        }
        let trimmedMessage = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty,
              request.message.utf8.count <= Self.maximumMessageBytes else {
            throw WorkflowMessageFileRelayError.invalidRequest("the message is empty or exceeds 64 KiB")
        }
        let age = Date().timeIntervalSince1970 - request.createdAtEpochSeconds
        guard age >= -60, age <= Self.maximumRequestAge else {
            throw WorkflowMessageFileRelayError.invalidRequest("the request is stale")
        }
        return request
    }

    private func write(result: WorkflowMessageRelayResult, removingClaimAt claimedURL: URL) {
        let resultURL = resultsDirectoryURL
            .appendingPathComponent("\(result.requestID).json", isDirectory: false)
        do {
            let data = try JSONEncoder().encode(result)
            try MapofAgentsPrivateFile.write(data, to: resultURL)
            try FileManager.default.removeItem(at: claimedURL)
        } catch {
            // Preserve the claimed file. The next app launch will report an
            // ambiguous outcome without replaying the provider turn.
        }
    }

    private func queueFiles(in directoryURL: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            guard url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: keys) else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func pruneStaleResults() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in queueFiles(in: resultsDirectoryURL) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modificationDate = values?.contentModificationDate,
                  modificationDate < cutoff else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static let helperScript = #"""
    #!/usr/bin/python3
    import argparse
    import json
    import os
    import stat
    import sys
    import time
    import uuid

    MAX_MESSAGE_BYTES = 64 * 1024
    WAIT_SECONDS = 35 * 60
    ROOT = os.path.dirname(os.path.realpath(__file__))
    PENDING = os.path.join(ROOT, "pending")
    RESULTS = os.path.join(ROOT, "results")

    def fail(message, status=2):
        print(json.dumps({"success": False, "detail": message}), flush=True)
        raise SystemExit(status)

    def require_private_directory(path):
        try:
            info = os.lstat(path)
        except OSError as error:
            fail("MapofAgents relay directory is unavailable: " + str(error))
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            fail("MapofAgents relay directory failed its ownership or permissions check")

    parser = argparse.ArgumentParser(description="Send a message to a thread on the active MapofAgents canvas.")
    parser.add_argument("--source-provider", required=True, choices=("codex", "gemini", "grok"))
    parser.add_argument("--source-host", required=True)
    parser.add_argument("--source-thread", required=True)
    parser.add_argument("--target-provider", required=True, choices=("codex", "gemini", "grok"))
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-thread", required=True)
    args = parser.parse_args()

    message_data = sys.stdin.buffer.read(MAX_MESSAGE_BYTES + 1)
    if len(message_data) > MAX_MESSAGE_BYTES:
        fail("Message exceeds 64 KiB")
    try:
        message = message_data.decode("utf-8").strip()
    except UnicodeDecodeError:
        fail("Message must be UTF-8")
    if not message:
        fail("Message is empty")

    require_private_directory(ROOT)
    require_private_directory(PENDING)
    require_private_directory(RESULTS)

    request_id = str(uuid.uuid4())
    request = {
        "requestID": request_id,
        "sourceProvider": args.source_provider,
        "sourceHostID": args.source_host,
        "sourceThreadID": args.source_thread,
        "targetProvider": args.target_provider,
        "targetHostID": args.target_host,
        "targetThreadID": args.target_thread,
        "message": message,
        "createdAtEpochSeconds": time.time(),
    }
    pending_path = os.path.join(PENDING, request_id + ".json")
    temporary_path = os.path.join(PENDING, "." + request_id + ".tmp")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(temporary_path, flags, 0o600)
    try:
        payload = json.dumps(request, separators=(",", ":")).encode("utf-8")
        os.write(descriptor, payload)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.replace(temporary_path, pending_path)

    result_path = os.path.join(RESULTS, request_id + ".json")
    deadline = time.monotonic() + WAIT_SECONDS
    while time.monotonic() < deadline:
        try:
            flags = os.O_RDONLY
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            descriptor = os.open(result_path, flags)
        except FileNotFoundError:
            time.sleep(0.2)
            continue
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 1024 * 1024:
                fail("MapofAgents returned an invalid relay result")
            chunks = []
            while True:
                chunk = os.read(descriptor, 64 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
            result_data = b"".join(chunks)
        finally:
            os.close(descriptor)
        try:
            os.unlink(result_path)
        except OSError:
            pass
        result = json.loads(result_data.decode("utf-8"))
        print(json.dumps(result, ensure_ascii=False), flush=True)
        raise SystemExit(0 if result.get("success") is True else 1)

    fail("Timed out waiting for MapofAgents. Delivery outcome is unknown; do not retry automatically.", 1)
    """#
    #endif
}
