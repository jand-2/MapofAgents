import Foundation

public enum ChatInputAttachmentError: Error, LocalizedError {
    case missingData(String)
    case tooLarge(String, Int, Int)
    case unsafeRemoteStagingRoot(String)

    public var errorDescription: String? {
        switch self {
        case .missingData(let name):
            return "Could not read attachment \"\(name)\"."
        case .tooLarge(let name, let size, let limit):
            return "\"\(name)\" is too large to attach (\(Self.formattedBytes(size)); limit is \(Self.formattedBytes(limit))."
        case .unsafeRemoteStagingRoot(let cwd):
            return "Could not derive a private per-user attachment directory from the remote working directory \"\(cwd)\". Provide the authenticated host's explicit application-support directory before sending attachments."
        }
    }

    private static func formattedBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

public enum ChatInputAttachmentService {
    public static let maxAttachmentBytes = 50 * 1024 * 1024
    public static let stagingDirectoryName = "attachment-staging"

    public static func sanitizedFileName(_ name: String, fallback: String = "attachment") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? fallback : trimmed
        let separators = CharacterSet(charactersIn: "/\\:")
            .union(.controlCharacters)
        let sanitized = candidate
            .components(separatedBy: separators)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = sanitized == "." || sanitized == ".." ? fallback : sanitized
        guard !safeName.isEmpty else { return fallback }
        return String(safeName.prefix(180))
    }

    public static func kind(forFileName name: String, mimeType: String? = nil) -> ChatInputAttachmentKind {
        if let mimeType, mimeType.lowercased().hasPrefix("image/") {
            return .image
        }
        return isImageFileName(name) ? .image : .file
    }

    public static func isImageFileName(_ name: String) -> Bool {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp":
            return true
        default:
            return false
        }
    }

    public static func inferredMimeType(forFileName name: String) -> String? {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "heic", "heif":
            return "image/heic"
        case "webp":
            return "image/webp"
        case "tif", "tiff":
            return "image/tiff"
        case "bmp":
            return "image/bmp"
        case "pdf":
            return "application/pdf"
        case "json":
            return "application/json"
        case "csv":
            return "text/csv"
        case "txt", "md", "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "html", "css", "xml", "yaml", "yml", "toml":
            return "text/plain"
        default:
            return nil
        }
    }

    /// Builds a host-side staging directory without placing generated files in
    /// the user's workspace. `stagingRoot` should be an app-owned support or
    /// cache directory on the target host.
    public static func remoteAttachmentDirectory(
        stagingRoot: String,
        hostID: HostID? = nil,
        threadID: String,
        stagingID: String = UUID().uuidString
    ) -> String {
        var components = ["hosts", sanitizedFileName(hostID?.rawValue ?? "remote", fallback: "remote")]
        components.append(contentsOf: [
            "threads",
            sanitizedFileName(threadID, fallback: "thread"),
            "batches",
            sanitizedFileName(stagingID, fallback: "batch"),
        ])
        return components.reduce(stagingRoot.trimmingTrailingPathSeparators()) { directory, component in
            joinedPath(directory: directory, fileName: component)
        }
    }

    /// Compatibility entry point for relays that have not yet received an
    /// explicit host support root. It accepts only paths whose per-user support
    /// directory can be derived without using a shared temp directory. The cwd
    /// itself is never used as the staging root.
    public static func remoteAttachmentDirectory(
        cwd: String,
        hostID: HostID? = nil,
        threadID: String,
        stagingID: String = UUID().uuidString
    ) throws -> String {
        guard let stagingRoot = inferredRemoteAttachmentStagingRoot(cwd: cwd) else {
            throw ChatInputAttachmentError.unsafeRemoteStagingRoot(cwd)
        }
        return remoteAttachmentDirectory(
            stagingRoot: stagingRoot,
            hostID: hostID,
            threadID: threadID,
            stagingID: stagingID
        )
    }

    public static func defaultLocalAttachmentStagingRoot(
        fileManager: FileManager = .default
    ) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("mapofagents", isDirectory: true)
            .appendingPathComponent(stagingDirectoryName, isDirectory: true)
    }

    public static func localAttachmentDirectory(
        for threadRef: ThreadRef,
        stagingRoot: URL? = nil,
        stagingID: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try stagingRoot ?? defaultLocalAttachmentStagingRoot(fileManager: fileManager)
        let directory = root
            .appendingPathComponent("hosts", isDirectory: true)
            .appendingPathComponent(sanitizedFileName(threadRef.hostID.rawValue, fallback: "local"), isDirectory: true)
            .appendingPathComponent("threads", isDirectory: true)
            .appendingPathComponent(sanitizedFileName(threadRef.threadID, fallback: "thread"), isDirectory: true)
            .appendingPathComponent("batches", isDirectory: true)
            .appendingPathComponent(sanitizedFileName(stagingID, fallback: "batch"), isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }

    public static func joinedPath(directory: String, fileName: String) -> String {
        let safeName = sanitizedFileName(fileName)
        if isWindowsPath(directory) || directory.contains("\\") {
            return directory.trimmingCharacters(in: CharacterSet(charactersIn: "\\/")) + "\\" + safeName
        }
        return directory.trimmingTrailingPathSeparators() + "/" + safeName
    }

    public static func attachmentData(_ attachment: ChatInputAttachment) throws -> Data {
        if let byteCount = attachment.byteCount {
            try validateSize(byteCount, name: attachment.name)
        }

        if let data = attachment.data {
            try validateSize(data.count, name: attachment.name)
            return data
        }

        guard let sourcePath = attachment.sourcePath else {
            throw ChatInputAttachmentError.missingData(attachment.name)
        }

        return try attachmentData(
            at: URL(fileURLWithPath: sourcePath, isDirectory: false),
            name: attachment.name
        )
    }

    /// Reads at most one byte beyond the attachment limit. File metadata is
    /// checked first so an obviously oversized source is rejected before any
    /// payload-sized allocation, while the bounded read also handles races and
    /// sources that do not report a trustworthy size.
    public static func attachmentData(at sourceURL: URL, name: String) throws -> Data {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let fileSize = attributes[.size] as? NSNumber {
            let size = fileSize.uint64Value
            if size > UInt64(maxAttachmentBytes) {
                throw ChatInputAttachmentError.tooLarge(
                    name,
                    maxAttachmentBytes + 1,
                    maxAttachmentBytes
                )
            }
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: sourceURL)
        } catch {
            throw ChatInputAttachmentError.missingData(name)
        }
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxAttachmentBytes + 1) ?? Data()
        try validateSize(data.count, name: name)
        return data
    }

    public static func validateSize(_ size: Int, name: String) throws {
        guard size <= maxAttachmentBytes else {
            throw ChatInputAttachmentError.tooLarge(name, size, maxAttachmentBytes)
        }
    }

    public static func inputItems(
        text: String,
        attachments: [ResolvedChatInputAttachment]
    ) -> [JSONValue] {
        var items: [JSONValue] = []
        let manifest = attachmentManifest(for: attachments)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textBody: String
        if trimmedText.isEmpty {
            textBody = manifest.isEmpty ? "Attached supplemental context." : manifest
        } else if manifest.isEmpty {
            textBody = trimmedText
        } else {
            textBody = trimmedText + "\n\n" + manifest
        }

        if !textBody.isEmpty {
            items.append(.object([
                "type": .string("text"),
                "text": .string(textBody),
                "text_elements": .array([]),
            ]))
        }

        for attachment in attachments where attachment.kind == .image {
            items.append(.object([
                "type": .string("localImage"),
                "path": .string(attachment.path),
            ]))
        }

        return items
    }

    private static func attachmentManifest(for attachments: [ResolvedChatInputAttachment]) -> String {
        guard !attachments.isEmpty else { return "" }
        let lines = attachments.map { attachment in
            let size = attachment.byteCount.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
            let suffix = [attachment.kind.displayName.lowercased(), size].compactMap { $0 }.joined(separator: ", ")
            let detail = suffix.isEmpty ? "" : " (\(suffix))"
            return "- \(attachment.name)\(detail): \(attachment.path)"
        }
        return "Attached supplemental files:\n" + lines.joined(separator: "\n")
    }

    private static func isWindowsPath(_ path: String) -> Bool {
        path.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    private static func inferredRemoteAttachmentStagingRoot(cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if isWindowsPath(trimmed) {
            let components = trimmed
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .map(String.init)
            if components.count >= 3,
               components[1].caseInsensitiveCompare("Users") == .orderedSame {
                let rawUser = components[2]
                guard let user = safeInferredProfileName(rawUser) else { return nil }
                return #"\#(components[0])\Users\\#(user)\AppData\Local\MapofAgents\attachment-staging"#
            }
            return nil
        }

        let components = trimmed.split(separator: "/").map(String.init)
        if trimmed.hasPrefix("/Users/"), components.count >= 2 {
            let rawUser = components[1]
            guard let user = safeInferredProfileName(rawUser) else { return nil }
            return "/Users/\(user)/Library/Application Support/mapofagents/attachment-staging"
        }
        if trimmed.hasPrefix("/home/"), components.count >= 2 {
            let rawUser = components[1]
            guard let user = safeInferredProfileName(rawUser) else { return nil }
            return "/home/\(user)/.local/share/mapofagents/attachment-staging"
        }
        return nil
    }

    private static func safeInferredProfileName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == rawValue,
              !trimmed.hasPrefix("."),
              sanitizedFileName(trimmed, fallback: "") == trimmed,
              !reservedSharedProfileNames.contains(trimmed.lowercased()) else {
            return nil
        }
        return trimmed
    }

    private static let reservedSharedProfileNames: Set<String> = [
        "all users",
        "default",
        "default user",
        "defaultapppool",
        "defaultuser0",
        "guest",
        "guests",
        "localservice",
        "networkservice",
        "nobody",
        "public",
        "shared",
        "systemprofile",
    ]
}

private extension String {
    func trimmingTrailingPathSeparators() -> String {
        var result = self
        while result.count > 1,
              let last = result.last,
              last == "/" || last == "\\" {
            result.removeLast()
        }
        return result
    }
}
