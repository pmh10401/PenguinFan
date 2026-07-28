import Foundation

public actor SettingsStore {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.fileURL = baseURL
                .appendingPathComponent("M2MaxFanController", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
    }

    public func load() throws -> FanSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .safeDefaults
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(FanSettings.self, from: data).persistedCopy
    }

    public func save(_ settings: FanSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(settings.persistedCopy)
        try data.write(to: fileURL, options: .atomic)
    }
}
