import Foundation

public enum TranscriptAssetCache {
    public typealias AttachmentDataReader = (ThreadMessageAttachment) async throws -> Data?
    public static let maxCachedArtifactBytes = 8 * 1024 * 1024
    public static let maxCachedImageBytes = 16 * 1024 * 1024

    public struct ArtifactTooLargeError: Error, Sendable {
        public var byteCount: Int

        public init(byteCount: Int) {
            self.byteCount = byteCount
        }
    }

    @MainActor
    public static func resolveImages(
        in transcript: ThreadTranscript,
        reader: @escaping AttachmentDataReader
    ) async -> ThreadTranscript {
        await resolveArtifacts(in: transcript, reader: reader)
    }

    @MainActor
    public static func resolveArtifacts(
        in transcript: ThreadTranscript,
        reader: @escaping AttachmentDataReader
    ) async -> ThreadTranscript {
        var resolved = transcript

        for messageIndex in resolved.messages.indices {
            for attachmentIndex in resolved.messages[messageIndex].attachments.indices {
                resolved.messages[messageIndex].attachments[attachmentIndex] = await resolvedAttachment(
                    resolved.messages[messageIndex].attachments[attachmentIndex],
                    in: transcript.threadRef,
                    reader: reader
                )
            }
        }

        if var timeline = resolved.turnTimeline {
            for turnIndex in timeline.turns.indices {
                for itemIndex in timeline.turns[turnIndex].items.indices {
                    for attachmentIndex in timeline.turns[turnIndex].items[itemIndex].attachments.indices {
                        timeline.turns[turnIndex].items[itemIndex].attachments[attachmentIndex] = await resolvedAttachment(
                            timeline.turns[turnIndex].items[itemIndex].attachments[attachmentIndex],
                            in: transcript.threadRef,
                            reader: reader
                        )
                    }
                }
            }
            resolved.turnTimeline = timeline
        }

        return resolved
    }

    @MainActor
    private static func resolvedAttachment(
        _ attachment: ThreadMessageAttachment,
        in threadRef: ThreadRef,
        reader: @escaping AttachmentDataReader
    ) async -> ThreadMessageAttachment {
        var resolved = attachment
        guard attachment.kind == .image || attachment.kind == .file || attachment.kind == .diff else {
            return resolved
        }

        if attachment.kind == .diff {
            if attachment.diffText != nil {
                resolved.status = attachment.status ?? "completed"
            }
            return resolved
        }

        if let cachedPath = attachment.cachedPath,
           FileManager.default.fileExists(atPath: cachedPath) {
            return resolved
        }

        guard attachment.isTrustedForAutoHydration else {
            return resolved
        }

        if let byteCount = attachment.byteCount,
           let limit = maxCachedBytes(for: attachment),
           byteCount > limit {
            resolved.status = "too-large"
            return resolved
        }

        let data: Data
        do {
            guard let readData = try await reader(attachment) else {
                if attachment.kind == .file {
                    resolved.status = "unavailable"
                }
                return resolved
            }
            data = readData
        } catch let error as ArtifactTooLargeError {
            resolved.status = "too-large"
            resolved.byteCount = error.byteCount
            return resolved
        } catch {
            if attachment.kind == .file {
                resolved.status = "unavailable"
            }
            return resolved
        }

        if let limit = maxCachedBytes(for: attachment), data.count > limit {
            resolved.status = "too-large"
            resolved.byteCount = data.count
            return resolved
        }

        guard let cachedURL = try? await cache(data: data, for: attachment, in: threadRef) else {
            return resolved
        }

        resolved.cachedPath = cachedURL.path
        resolved.status = "completed"
        resolved.byteCount = data.count
        if resolved.mimeType == nil {
            resolved.mimeType = mimeType(forPath: attachment.sourcePath ?? cachedURL.path)
        }
        if resolved.language == nil {
            resolved.language = language(forPath: attachment.sourcePath ?? cachedURL.path)
        }
        return resolved
    }

    public static func maxCachedBytes(for attachment: ThreadMessageAttachment) -> Int? {
        switch attachment.kind {
        case .file:
            return maxCachedArtifactBytes
        case .image:
            return maxCachedImageBytes
        case .diff:
            return nil
        }
    }

    public static func cachedAssetDirectory(for threadRef: ThreadRef) throws -> URL {
        let paths = try ApplicationPaths.defaultPaths()
        return paths.applicationSupportDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent(sanitize(threadRef.hostID.rawValue), isDirectory: true)
            .appendingPathComponent(sanitize(threadRef.threadID), isDirectory: true)
    }

    public static func sourceReadPath(
        for attachment: ThreadMessageAttachment,
        in threadRef: ThreadRef
    ) -> String? {
        guard let sourcePath = attachment.sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourcePath.isEmpty else {
            return nil
        }

        let resolvedPath = resolvedArtifactPath(sourcePath, cwd: threadRef.cwd)
        guard isAllowedArtifactPath(resolvedPath, threadRef: threadRef) else {
            return nil
        }
        return resolvedPath
    }

    public static func resolvedArtifactPath(_ sourcePath: String, cwd: String) -> String {
        let trimmedSource = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty,
              !isAbsolutePath(trimmedSource),
              !trimmedSource.hasPrefix("~")
        else {
            return trimmedSource
        }

        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCWD.isEmpty else {
            return trimmedSource
        }

        let separator = usesWindowsSeparators(trimmedCWD) ? "\\" : "/"
        let base = trimmingTrailingPathSeparators(trimmedCWD)
        let relative = trimmedSource.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
        if base == "/" || base.hasSuffix("\\") || base.hasSuffix("/") {
            return base + relative
        }
        return base + separator + relative
    }

    private static func isAllowedArtifactPath(_ path: String, threadRef: ThreadRef) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedPath.hasPrefix("~") else {
            return false
        }

        let normalizedPath = comparablePath(trimmedPath)
        guard !normalizedPath.isEmpty else {
            return false
        }

        let normalizedCWD = comparablePath(threadRef.cwd)
        if isUsableArtifactRoot(normalizedCWD),
           isPathSafelyWithinRoot(trimmedPath, root: threadRef.cwd) {
            return true
        }

        if let generatedRoot = threadScopedGeneratedArtifactRoot(in: normalizedPath, threadID: threadRef.threadID),
           isPathSafelyWithinRoot(trimmedPath, root: generatedRoot) {
            return true
        }

        return false
    }

    private static func threadScopedGeneratedArtifactRoot(in path: String, threadID: String) -> String? {
        let safeThreadID = sanitize(threadID).lowercased()
        let patterns = [
            "/.mapofagents/attachments/\(safeThreadID)",
            "/.codex/generated_images/\(safeThreadID)",
        ]
        for pattern in patterns {
            guard let range = path.range(of: pattern),
                  range.upperBound == path.endIndex || path[range.upperBound] == "/" else {
                continue
            }
            return String(path[..<range.upperBound])
        }
        return nil
    }

    private static func isPathSafelyWithinRoot(_ path: String, root: String) -> Bool {
        let normalizedPath = comparablePath(path)
        let normalizedRoot = comparablePath(root)
        guard isUsableArtifactRoot(normalizedRoot),
              isPath(normalizedPath, within: normalizedRoot)
        else {
            return false
        }

        guard let resolvedPath = symlinkResolvedComparablePath(path),
              let resolvedRoot = symlinkResolvedComparablePath(root)
        else {
            return true
        }

        return isUsableArtifactRoot(resolvedRoot) && isPath(resolvedPath, within: resolvedRoot)
    }

    private static func isPath(_ path: String, within root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func isUsableArtifactRoot(_ root: String) -> Bool {
        guard !root.isEmpty, root != "/", root != "//" else {
            return false
        }
        if root.range(of: #"^[a-z]:/$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func symlinkResolvedComparablePath(_ path: String) -> String? {
        guard path.hasPrefix("/") else {
            return nil
        }
        let resolved = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard !resolved.isEmpty else {
            return nil
        }
        return comparablePath(resolved)
    }

    private static func comparablePath(_ path: String) -> String {
        let unified = path.replacingOccurrences(of: "\\", with: "/")
        let lowercased = unified.lowercased()

        let root: String
        let body: String
        if lowercased.hasPrefix("//") {
            root = "//"
            body = String(unified.dropFirst(2))
        } else if lowercased.hasPrefix("/") {
            root = "/"
            body = String(unified.dropFirst())
        } else if unified.count >= 2, unified[unified.index(after: unified.startIndex)] == ":" {
            root = String(unified.prefix(2)).lowercased() + "/"
            body = String(unified.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            root = ""
            body = unified
        }

        var components: [String] = []
        for rawPart in body.split(separator: "/", omittingEmptySubsequences: true) {
            let part = String(rawPart)
            switch part {
            case ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(part)
            }
        }

        return root + components.joined(separator: "/").lowercased()
    }

    private static func cache(
        data: Data,
        for attachment: ThreadMessageAttachment,
        in threadRef: ThreadRef
    ) async throws -> URL {
        let directory = try cachedAssetDirectory(for: threadRef)
        let url = directory.appendingPathComponent(cachedFileName(for: attachment))

        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        }.value

        return url
    }

    private static func cachedFileName(for attachment: ThreadMessageAttachment) -> String {
        let ext = fileExtension(for: attachment)
        return "\(sanitize(attachment.id)).\(ext)"
    }

    private static func fileExtension(for attachment: ThreadMessageAttachment) -> String {
        if attachment.kind == .diff {
            return "diff"
        }

        if let sourcePath = attachment.sourcePath {
            let pathExtension = URL(fileURLWithPath: sourcePath).pathExtension
            if !pathExtension.isEmpty {
                return pathExtension.lowercased()
            }
        }

        if attachment.kind == .file {
            switch attachment.mimeType?.lowercased() {
            case "application/json":
                return "json"
            case "text/markdown":
                return "md"
            case "text/html":
                return "html"
            case "text/css":
                return "css"
            case "text/javascript":
                return "js"
            default:
                return "txt"
            }
        }

        switch attachment.mimeType?.lowercased() {
        case "image/jpeg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        case "image/heic":
            return "heic"
        default:
            return "png"
        }
    }

    public static func mimeType(forPath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "json":
            return "application/json"
        case "pdf":
            return "application/pdf"
        case "md", "markdown":
            return "text/markdown"
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "js", "mjs", "cjs":
            return "text/javascript"
        case "swift", "txt", "log", "diff", "patch", "py", "rb", "go", "rs", "java", "kt", "ts", "tsx", "jsx", "yml", "yaml", "toml", "sh", "zsh", "ps1":
            return "text/plain"
        default:
            return nil
        }
    }

    public static func language(forPath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift":
            return "swift"
        case "json":
            return "json"
        case "md", "markdown":
            return "markdown"
        case "html", "htm":
            return "html"
        case "css":
            return "css"
        case "js", "mjs", "cjs", "jsx":
            return "javascript"
        case "ts", "tsx":
            return "typescript"
        case "py":
            return "python"
        case "rb":
            return "ruby"
        case "go":
            return "go"
        case "rs":
            return "rust"
        case "java":
            return "java"
        case "kt":
            return "kotlin"
        case "yml", "yaml":
            return "yaml"
        case "toml":
            return "toml"
        case "sh", "zsh":
            return "shell"
        case "ps1":
            return "powershell"
        case "diff", "patch":
            return "diff"
        default:
            return nil
        }
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/")
            || path.hasPrefix("\\\\")
            || path.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    private static func usesWindowsSeparators(_ path: String) -> Bool {
        path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil
            || path.contains("\\")
    }

    private static func trimmingTrailingPathSeparators(_ path: String) -> String {
        var result = path
        while result.count > minimumRootLength(for: result),
              let last = result.last,
              last == "/" || last == "\\" {
            result.removeLast()
        }
        return result
    }

    private static func minimumRootLength(for path: String) -> Int {
        if path.range(of: #"^[A-Za-z]:[\\/]$"#, options: .regularExpression) != nil {
            return 3
        }
        if path.hasPrefix("/") || path.hasPrefix("\\\\") {
            return 1
        }
        return 0
    }

    private static func sanitize(_ value: String) -> String {
        let sanitized = value.map { character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let result = String(sanitized)
        return result.isEmpty ? "asset" : result
    }
}
