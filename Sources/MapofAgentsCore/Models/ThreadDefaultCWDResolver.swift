import Foundation

public enum ThreadDefaultCWDResolver {
    public static func defaultCWD(
        for machine: CanvasNode,
        localHostID: HostID,
        localDefaultDirectory: String? = nil
    ) -> String? {
        if let codexHome = machine.metadata.codexHome?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            let fallbackDirectory = machine.metadata.hostID == localHostID ? localDefaultDirectory : nil
            return usableDefaultDirectory(
                parentDirectory(
                    of: codexHome,
                    platform: machine.metadata.platform,
                    fallbackDirectory: fallbackDirectory
                )
            ) ?? usableDefaultDirectory(fallbackDirectory)
        }

        if machine.metadata.hostID == localHostID,
           let localDefaultDirectory = usableDefaultDirectory(localDefaultDirectory) {
            return localDefaultDirectory
        }

        switch machine.metadata.platform {
        case .windows:
            return #"C:\Users\User"#
        case .macOS, .iOS, .iPadOS, .linux, .unknown, .none:
            return nil
        }
    }

    private static func usableDefaultDirectory(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              !isRootDirectory(path)
        else {
            return nil
        }
        return path
    }

    private static func isRootDirectory(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/" || trimmed == "\\" || trimmed == "//" {
            return true
        }
        if trimmed.range(of: #"^[A-Za-z]:[\\/]*$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func parentDirectory(
        of path: String,
        platform: HostPlatform?,
        fallbackDirectory: String? = nil
    ) -> String {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDirectory = fallbackDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)

        if path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
            let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            guard let lastSeparator = trimmed.lastIndex(of: "\\") ?? trimmed.lastIndex(of: "/") else {
                return path
            }
            return String(trimmed[..<lastSeparator])
        }

        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !parent.isEmpty {
            return parent
        }

        if let fallbackDirectory, !fallbackDirectory.isEmpty {
            return fallbackDirectory
        }

        return platform == .windows ? #"C:\Users\User"# : "/"
    }
}
