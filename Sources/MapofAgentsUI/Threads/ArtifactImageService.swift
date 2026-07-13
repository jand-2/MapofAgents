import Foundation

#if os(macOS)
import AppKit
typealias ArtifactPlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias ArtifactPlatformImage = UIImage
#endif

/// A sendable boundary around immutable decoded image data. AppKit and UIKit do
/// not annotate their image classes as Sendable, but decoding and immutable
/// display use are thread-safe for this narrowly owned value.
struct DecodedArtifactImage: @unchecked Sendable {
    let image: ArtifactPlatformImage
}

/// Performs file I/O and image decoding away from SwiftUI's main actor and
/// keeps a small process-local cache for repeated transcript/preview renders.
actor ArtifactImageService {
    static let shared = ArtifactImageService()

    private let capacity: Int
    private var images: [String: DecodedArtifactImage] = [:]
    private var accessOrder: [String] = []

    init(capacity: Int = 24) {
        self.capacity = max(1, capacity)
    }

    func image(at path: String) async -> DecodedArtifactImage? {
        if let cached = images[path] {
            markRecentlyUsed(path)
            return cached
        }

        let decoded = await Task.detached(priority: .utility) {
            ArtifactPlatformImage(contentsOfFile: path).map(DecodedArtifactImage.init)
        }.value
        guard !Task.isCancelled, let decoded else { return nil }

        images[path] = decoded
        markRecentlyUsed(path)
        while accessOrder.count > capacity, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            images[oldest] = nil
        }
        return decoded
    }

    private func markRecentlyUsed(_ path: String) {
        accessOrder.removeAll { $0 == path }
        accessOrder.append(path)
    }
}

/// The UI-facing artifact boundary. Views no longer perform unbounded reads or
/// copy files themselves; they request decoded images, bounded text previews,
/// and exported copies through this service.
actor ArtifactService {
    static let shared = ArtifactService()

    private let imageService: ArtifactImageService

    init(imageService: ArtifactImageService = .shared) {
        self.imageService = imageService
    }

    func image(at path: String) async -> DecodedArtifactImage? {
        await imageService.image(at: path)
    }

    func textPreview(at path: String, maximumBytes: Int = 240_000) async -> String? {
        let boundedMaximum = max(1, maximumBytes)
        return await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }

            guard let data = try? handle.read(upToCount: boundedMaximum + 1) else { return nil }
            let wasTruncated = data.count > boundedMaximum
            let previewData = wasTruncated ? data.prefix(boundedMaximum) : data[...]
            guard var text = String(data: Data(previewData), encoding: .utf8) else { return nil }
            if wasTruncated {
                text += "\n\n... file truncated for preview ..."
            }
            return text
        }.value
    }

    func saveCopy(from sourceURL: URL, preferredName: String) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let destinationDirectory = try Self.destinationDirectory(fileManager: fileManager)
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destinationURL = Self.uniqueDestinationURL(
                in: destinationDirectory,
                preferredName: preferredName,
                fileManager: fileManager
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        }.value
    }

    nonisolated static func fileName(_ path: String) -> String {
        path
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? path
    }

    nonisolated static func pathExtension(_ path: String) -> String {
        let name = fileName(path)
        guard let dotIndex = name.lastIndex(of: "."),
              dotIndex < name.index(before: name.endIndex) else {
            return ""
        }
        return String(name[name.index(after: dotIndex)...]).lowercased()
    }

    nonisolated static func formattedBytes(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private nonisolated static func destinationDirectory(fileManager: FileManager) throws -> URL {
        #if os(macOS)
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        #endif

        return try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private nonisolated static func uniqueDestinationURL(
        in directory: URL,
        preferredName: String,
        fileManager: FileManager
    ) -> URL {
        let baseURL = directory.appendingPathComponent(preferredName.isEmpty ? "artifact" : preferredName)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

        let name = baseURL.deletingPathExtension().lastPathComponent
        let pathExtension = baseURL.pathExtension
        for index in 2...999 {
            let candidateName = pathExtension.isEmpty
                ? "\(name)-\(index)"
                : "\(name)-\(index).\(pathExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        let fallback = directory.appendingPathComponent(UUID().uuidString)
        return pathExtension.isEmpty ? fallback : fallback.appendingPathExtension(pathExtension)
    }
}
