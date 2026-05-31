import Foundation

public protocol SemanticEdgeResolving: Sendable {
    func resolveEdges(in graph: AgentGraph) -> [CanvasEdge]
}

public struct DefaultSemanticEdgeResolver: SemanticEdgeResolving {
    public init() {}

    public func resolveEdges(in graph: AgentGraph) -> [CanvasEdge] {
        let nodes = Array(graph.nodes.values)
        let machines = nodes.filter { $0.kind == .machine }
        let folders = nodes.filter { $0.kind == .folder }
        let threads = nodes.filter { $0.kind == .codexThread }
        let semanticParentThreads = threads.filter { $0.metadata.threadKind != .subagent }

        var edges: [CanvasEdge] = []
        var projectThreadIDs = Set<NodeID>()

        for machine in machines {
            for folder in folders where folder.metadata.hostID == machine.metadata.hostID {
                edges.append(
                    semanticEdge(
                        source: machine.id,
                        target: folder.id,
                        kind: .machineFolder,
                        label: nil
                    )
                )
            }
        }

        for thread in semanticParentThreads {
            guard let threadRef = thread.metadata.threadRef else { continue }

            let matchingFolders = folders.compactMap { folder -> FolderMatch? in
                guard
                    let folderPath = folder.metadata.folderPath,
                    let folderHostID = folder.metadata.hostID,
                    threadRef.hostID == folderHostID
                else {
                    return nil
                }

                let caseInsensitive = Self.usesCaseInsensitivePaths(folder: folder, thread: thread)
                guard let normalizedFolderPath = Self.path(
                    threadRef.cwd,
                    matchInsideOrEqualTo: folderPath,
                    caseInsensitive: caseInsensitive
                ) else {
                    return nil
                }

                return FolderMatch(folder: folder, normalizedPath: normalizedFolderPath)
            }
            .sorted { lhs, rhs in
                if lhs.normalizedPath.specificity != rhs.normalizedPath.specificity {
                    return lhs.normalizedPath.specificity > rhs.normalizedPath.specificity
                }
                return lhs.folder.id.rawValue < rhs.folder.id.rawValue
            }

            guard let folder = matchingFolders.first?.folder else {
                continue
            }

            projectThreadIDs.insert(thread.id)
            edges.append(
                semanticEdge(
                    source: folder.id,
                    target: thread.id,
                    kind: .folderThread,
                    label: nil
                )
            )
        }

        for machine in machines {
            for thread in semanticParentThreads where thread.metadata.threadRef?.hostID == machine.metadata.hostID && !projectThreadIDs.contains(thread.id) {
                edges.append(
                    semanticEdge(
                        source: machine.id,
                        target: thread.id,
                        kind: .machineThread,
                        label: nil
                    )
                )
            }
        }

        return edges
    }

    private func semanticEdge(
        source: NodeID,
        target: NodeID,
        kind: EdgeKind,
        label: String?
    ) -> CanvasEdge {
        CanvasEdge(
            id: EdgeID(rawValue: "semantic-\(kind.rawValue)-\(source.rawValue)-\(target.rawValue)"),
            source: source,
            target: target,
            kind: kind,
            isManual: false,
            label: label
        )
    }

    private static func path(
        _ path: String,
        matchInsideOrEqualTo root: String,
        caseInsensitive: Bool
    ) -> NormalizedPath? {
        let normalizedRoot = standardize(root, caseInsensitive: caseInsensitive)
        let normalizedPath = standardize(path, caseInsensitive: caseInsensitive)

        if normalizedPath.value == normalizedRoot.value {
            return normalizedRoot
        }

        let rootWithSlash = normalizedRoot.value.hasSuffix("/") ? normalizedRoot.value : normalizedRoot.value + "/"
        return normalizedPath.value.hasPrefix(rootWithSlash) ? normalizedRoot : nil
    }

    private static func standardize(_ path: String, caseInsensitive: Bool) -> NormalizedPath {
        let slashNormalized = path.replacingOccurrences(of: "\\", with: "/")
        let pathIsWindowsStyle = isWindowsStylePath(slashNormalized)
        let standardized: String

        if pathIsWindowsStyle {
            standardized = trimTrailingSlashes(collapseSlashes(slashNormalized))
        } else {
            standardized = trimTrailingSlashes(NSString(string: slashNormalized).standardizingPath)
        }

        let value = (caseInsensitive || pathIsWindowsStyle) ? standardized.lowercased() : standardized
        let segments = value.split(separator: "/").map(String.init)
        return NormalizedPath(value: value, specificity: segments.reduce(0) { $0 + $1.count } + segments.count)
    }

    private static func usesCaseInsensitivePaths(folder: CanvasNode, thread: CanvasNode) -> Bool {
        folder.metadata.platform == .windows
            || thread.metadata.platform == .windows
            || folder.metadata.folderPath.map(isWindowsStylePath) == true
            || thread.metadata.threadRef.map { isWindowsStylePath($0.cwd) } == true
    }

    private static func isWindowsStylePath(_ path: String) -> Bool {
        path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil
            || path.hasPrefix("//")
            || path.hasPrefix("\\\\")
    }

    private static func collapseSlashes(_ path: String) -> String {
        let hasUNCPrefix = path.hasPrefix("//")
        let collapsed = path.replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
        guard hasUNCPrefix, !collapsed.hasPrefix("//") else {
            return collapsed
        }
        return "/" + collapsed
    }

    private static func trimTrailingSlashes(_ path: String) -> String {
        guard path.count > 1 else {
            return path
        }

        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private struct FolderMatch {
        var folder: CanvasNode
        var normalizedPath: NormalizedPath
    }

    private struct NormalizedPath {
        var value: String
        var specificity: Int
    }
}
