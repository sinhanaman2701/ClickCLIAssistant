import Foundation

public enum ConfigStore {
    public static func load() throws -> AppConfig {
        let url = AppPaths.configFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.missingConfig
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public static func save(_ config: AppConfig) throws {
        try AppPaths.ensureBaseDirectory()
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: AppPaths.configFile, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
