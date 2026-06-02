import Foundation

public enum CodexRemoteIdentityStore {
    public static func shouldImport(identityPath: String?) -> Bool {
        guard let identityPath, !identityPath.isEmpty else {
            return false
        }

        let expandedPath = expanded(identityPath)
        guard !isInMapofAgentsSupport(expandedPath) else {
            return false
        }

        let components = URL(fileURLWithPath: expandedPath).pathComponents
        return components.contains("Documents")
            || components.contains("Desktop")
            || components.contains("Downloads")
    }

    public static func preparedIdentityPath(for remote: CodexDesktopRemote) throws -> String? {
        guard let identityPath = remote.identityPath, !identityPath.isEmpty else {
            return nil
        }

        let expandedPath = expanded(identityPath)
        guard shouldImport(identityPath: expandedPath) else {
            return expandedPath
        }

        let source = URL(fileURLWithPath: expandedPath)
        let target = importedIdentityURL(for: remote, source: source)
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return target.path
        }

        try fileManager.copyItem(at: source, to: target)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target.path
    }

    public static func routeIdentityPath(for remote: CodexDesktopRemote) -> String? {
        guard let identityPath = remote.identityPath, !identityPath.isEmpty else {
            return nil
        }

        let expandedPath = expanded(identityPath)
        guard shouldImport(identityPath: expandedPath) else {
            return expandedPath
        }

        let source = URL(fileURLWithPath: expandedPath)
        let target = importedIdentityURL(for: remote, source: source)
        return FileManager.default.fileExists(atPath: target.path) ? target.path : nil
    }

    public static func importNotice(for remote: CodexDesktopRemote) -> String? {
        guard let identityPath = remote.identityPath, shouldImport(identityPath: identityPath) else {
            return nil
        }

        return """
        mapofagents needs the saved SSH key at:
        \(expanded(identityPath))

        To avoid repeated privacy prompts, it will copy that key into this app's local Application Support folder and use the local copy for future remote connections. macOS may ask once for permission to read the original key.
        """
    }

    public static func requiresPreparation(for remote: CodexDesktopRemote) -> Bool {
        guard let identityPath = remote.identityPath, shouldImport(identityPath: identityPath) else {
            return false
        }

        let source = URL(fileURLWithPath: expanded(identityPath))
        let target = importedIdentityURL(for: remote, source: source)
        return !FileManager.default.fileExists(atPath: target.path)
    }

    private static func importedIdentityURL(for remote: CodexDesktopRemote, source: URL) -> URL {
        let directory = mapofagentsSupportDirectory()
            .appendingPathComponent("ssh-keys", isDirectory: true)
        let remoteName = sanitized(remote.id.rawValue).nilIfBlank ?? "remote"
        let sourceName = source.lastPathComponent.isEmpty ? "identity" : source.lastPathComponent
        return directory.appendingPathComponent("\(remoteName)-\(sourceName)", isDirectory: false)
    }

    private static func mapofagentsSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(ApplicationPaths.supportDirectoryName, isDirectory: true)
    }

    private static func isInMapofAgentsSupport(_ path: String) -> Bool {
        let appSupportPath = mapofagentsSupportDirectory().standardizedFileURL.path
        let candidatePath = URL(fileURLWithPath: path).standardizedFileURL.path
        return candidatePath == appSupportPath
            || candidatePath.hasPrefix(appSupportPath + "/")
    }

    private static func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func expanded(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
