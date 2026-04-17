import Foundation

public enum AppPaths {
    public static let appSupportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ai-assistant", isDirectory: true)

    public static let configFile = appSupportDirectory.appendingPathComponent("config.json")

    public static let bootstrapSourceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".click-cli-assistant-src", isDirectory: true)

    public static let binDirectory = appSupportDirectory.appendingPathComponent("bin", isDirectory: true)

    public static let bridgeBinary = binDirectory.appendingPathComponent("click-assistant")

    public static let logsDirectory = appSupportDirectory.appendingPathComponent("logs", isDirectory: true)

    public static let launchAgentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("LaunchAgents", isDirectory: true)
        .appendingPathComponent("com.clickcliassistant.bridge.plist")

    public static func ensureBaseDirectory() throws {
        try FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}
