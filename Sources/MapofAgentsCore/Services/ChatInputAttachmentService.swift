import Foundation

public enum ChatInputAttachmentError: Error, LocalizedError {
    case missingData(String)
    case tooLarge(String, Int, Int)

    public var errorDescription: String? {
        switch self {
        case .missingData(let name):
            return "Could not read attachment \"\(name)\"."
        case .tooLarge(let name, let size, let limit):
            return "\"\(name)\" is too large to attach (\(Self.formattedBytes(size)); limit is \(Self.formattedBytes(limit))."
        }
    }

    private static func formattedBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

public enum ChatInputAttachmentService {
    public static let maxAttachmentBytes = 50 * 1024 * 1024

    public static func sanitizedFileName(_ name: String, fallback: String = "attachment") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? fallback : trimmed
        let separators = CharacterSet(charactersIn: "/\\:")
        let sanitized = candidate
            .components(separatedBy: separators)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
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

    public static func remoteAttachmentDirectory(cwd: String, threadID: String) -> String {
        let safeThreadID = sanitizedFileName(threadID, fallback: "thread")
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if isWindowsPath(trimmed) {
            let base = trimmed.isEmpty ? #"C:\Users\Public\Documents"# : trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
            return #"\#(base)\.mapofagents\attachments\\#(safeThreadID)"#
        }

        let base = trimmed.isEmpty ? "/tmp" : trimmed.trimmingTrailingPathSeparators()
        if base.hasPrefix("/") {
            return "\(base)/.mapofagents/attachments/\(safeThreadID)"
        }
        return "/tmp/mapofagents-attachments/\(safeThreadID)"
    }

    public static func localAttachmentDirectory(for threadRef: ThreadRef) throws -> URL {
        let threadID = sanitizedFileName(threadRef.threadID, fallback: "thread")
        let cwd = threadRef.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if cwd.hasPrefix("/") {
            return URL(fileURLWithPath: cwd, isDirectory: true)
                .appendingPathComponent(".mapofagents", isDirectory: true)
                .appendingPathComponent("attachments", isDirectory: true)
                .appendingPathComponent(threadID, isDirectory: true)
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("mapofagents", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent(threadID, isDirectory: true)
    }

    public static func joinedPath(directory: String, fileName: String) -> String {
        let safeName = sanitizedFileName(fileName)
        if isWindowsPath(directory) || directory.contains("\\") {
            return directory.trimmingCharacters(in: CharacterSet(charactersIn: "\\/")) + "\\" + safeName
        }
        return directory.trimmingTrailingPathSeparators() + "/" + safeName
    }

    public static func attachmentData(_ attachment: ChatInputAttachment) throws -> Data {
        if let data = attachment.data {
            try validateSize(data.count, name: attachment.name)
            return data
        }

        guard let sourcePath = attachment.sourcePath else {
            throw ChatInputAttachmentError.missingData(attachment.name)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        try validateSize(data.count, name: attachment.name)
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
