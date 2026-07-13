import Foundation

/// Whether a JSON-RPC call may be issued again after the transport disconnects
/// before its response arrives. The classification belongs to the protocol
/// method rather than to an individual caller so writes cannot accidentally opt
/// themselves into replay.
public enum AppServerReplaySafety: Equatable, Sendable {
    case replayableRead
    case nonReplayableWrite
}

/// Client-initiated Codex App Server methods used by MapofAgents.
///
/// Keeping these methods typed gives the local and remote sessions one source
/// of truth for replay and timeout behavior. New methods must be deliberately
/// classified before they can be sent.
public enum AppServerMethod: String, CaseIterable, Sendable {
    case initialize
    case accountRead = "account/read"
    case createDirectory = "fs/createDirectory"
    case readDirectory = "fs/readDirectory"
    case readFile = "fs/readFile"
    case writeFile = "fs/writeFile"
    case listModels = "model/list"
    case listPlugins = "plugin/list"
    case listSkills = "skills/list"
    case archiveThread = "thread/archive"
    case forkThread = "thread/fork"
    case listThreads = "thread/list"
    case listLoadedThreads = "thread/loaded/list"
    case setThreadName = "thread/name/set"
    case readThread = "thread/read"
    case resumeThread = "thread/resume"
    case searchThreads = "thread/search"
    case startThread = "thread/start"
    case listTurns = "thread/turns/list"
    case unsubscribeThread = "thread/unsubscribe"
    case interruptTurn = "turn/interrupt"
    case startTurn = "turn/start"

    public var replaySafety: AppServerReplaySafety {
        switch self {
        case .accountRead,
             .readDirectory,
             .readFile,
             .listModels,
             .listPlugins,
             .listSkills,
             .listThreads,
             .listLoadedThreads,
             .readThread,
             .searchThreads,
             .listTurns:
            return .replayableRead
        case .initialize,
             .createDirectory,
             .writeFile,
             .archiveThread,
             .forkThread,
             .setThreadName,
             .resumeThread,
             .startThread,
             .unsubscribeThread,
             .interruptTurn,
             .startTurn:
            return .nonReplayableWrite
        }
    }

    public var timeoutSeconds: Int {
        switch self {
        case .initialize:
            return 6
        case .startTurn:
            return 60
        default:
            return 20
        }
    }
}

public struct AppServerCall: Sendable {
    public var method: AppServerMethod
    public var params: JSONValue

    public init(_ method: AppServerMethod, params: JSONValue = .object([:])) {
        self.method = method
        self.params = params
    }
}
