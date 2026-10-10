import Foundation

public protocol ConfigPersisting: Sendable {
    func loadConfig() throws -> SafeShareConfig?
    func saveConfig(_ config: SafeShareConfig) throws
}

public final class FileConfigPersistence: @unchecked Sendable, ConfigPersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let safeShareDir = appSupport.appendingPathComponent("SafeShare", isDirectory: true)
            self.fileURL = safeShareDir.appendingPathComponent("config.json", isDirectory: false)
        }
    }

    public func loadConfig() throws -> SafeShareConfig? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(SafeShareConfig.self, from: data)
    }

    public func saveConfig(_ config: SafeShareConfig) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: [.atomic])
    }
}
