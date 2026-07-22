import Foundation

public struct BoundedProcessOutput: Sendable, Hashable {
    public var data: Data
    public var wasTruncated: Bool

    public init(data: Data, wasTruncated: Bool = false) {
        self.data = data
        self.wasTruncated = wasTruncated
    }

    public var stringValue: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

public struct BoundedProcessResult: Sendable, Hashable {
    public var terminationStatus: Int32
    public var stdout: BoundedProcessOutput
    public var stderr: BoundedProcessOutput

    public init(
        terminationStatus: Int32,
        stdout: BoundedProcessOutput,
        stderr: BoundedProcessOutput
    ) {
        self.terminationStatus = terminationStatus
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum BoundedProcessRunner {
    public static func runBlocking(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval,
        maxOutputBytes: Int = 1_048_576
    ) throws -> BoundedProcessResult {
        #if os(macOS)
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        final class CaptureBox: @unchecked Sendable {
            let lock = NSLock()
            var stdout = BoundedProcessOutput(data: Data())
            var stderr = BoundedProcessOutput(data: Data())
        }
        let capture = CaptureBox()
        let drainGroup = DispatchGroup()

        try process.run()

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let drained = drain(stdoutPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            capture.lock.lock()
            capture.stdout = drained
            capture.lock.unlock()
            drainGroup.leave()
        }

        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let drained = drain(stderrPipe.fileHandleForReading, maxBytes: maxOutputBytes)
            capture.lock.lock()
            capture.stderr = drained
            capture.lock.unlock()
            drainGroup.leave()
        }

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            waitGroup.leave()
        }

        if waitGroup.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
        }
        _ = waitGroup.wait(timeout: .now() + 1)
        _ = drainGroup.wait(timeout: .now() + 1)

        capture.lock.lock()
        let capturedStdout = capture.stdout
        let capturedStderr = capture.stderr
        capture.lock.unlock()

        return BoundedProcessResult(
            terminationStatus: process.isRunning ? -1 : process.terminationStatus,
            stdout: capturedStdout,
            stderr: capturedStderr
        )
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    public static func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeout: TimeInterval,
        maxOutputBytes: Int = 1_048_576
    ) async throws -> BoundedProcessResult {
        #if os(macOS)
        return try await Task.detached(priority: .utility) {
            try runBlocking(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout,
                maxOutputBytes: maxOutputBytes
            )
        }.value
        #else
        throw CodexAppServerError.unsupportedPlatform
        #endif
    }

    private static func drain(_ handle: FileHandle, maxBytes: Int) -> BoundedProcessOutput {
        var data = Data()
        var wasTruncated = false
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            if chunk.isEmpty {
                break
            }
            if data.count < maxBytes {
                let remaining = maxBytes - data.count
                data.append(contentsOf: chunk.prefix(remaining))
                if chunk.count > remaining {
                    wasTruncated = true
                }
            } else {
                wasTruncated = true
            }
        }
        return BoundedProcessOutput(data: data, wasTruncated: wasTruncated)
    }
}
