import Foundation

public enum AppPaths {
    public static let appSupportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ai-assistant", isDirectory: true)

    public static let configFile = appSupportDirectory.appendingPathComponent("config.json")

    public static func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}
